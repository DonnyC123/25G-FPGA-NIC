#define pr_fmt(fmt) KBUILD_MODNAME ":%s: " fmt, __func__

#include <linux/if_ether.h>
#include <linux/etherdevice.h>

#include "eth_mod.h"

int rx_clean_skb(struct xdma_rx_ring *rx_ring, int budget)
{
	struct net_device *net_dev;
	int packets_processed;
	u32 *ci;

	net_dev = rx_ring->net_dev;
	ci = &rx_ring->driver_ci;

	for (packets_processed = 0; packets_processed < budget; packets_processed++) {
		struct xdma_result *res = &rx_ring->hw_res_ring_virt[*ci];
		struct xdma_rx_buffer_info *bi = &rx_ring->sw_ring[*ci];
		struct sk_buff *skb;
		struct page *page;
		u32 len;

		if (!res->status)
			break;

		dma_rmb();
		res->status = 0;

		len = le32_to_cpu(res->length);
		page = bi->page;
		bi->page = NULL;
		bi->dma = 0;

		*ci = (*ci + 1) % rx_ring->count;

		if (unlikely(!len || len > rx_ring->buffer_len)) {
			net_dev->stats.rx_errors++;
			page_pool_recycle_direct(rx_ring->page_pool, page);
			continue;
		}

		dma_sync_single_for_cpu(rx_ring->dev,
					page_pool_get_dma_addr(page) + RX_HEADROOM,
					len, DMA_FROM_DEVICE);

		skb = napi_build_skb(page_address(page), PAGE_SIZE);
		if (unlikely(!skb)) {
			net_dev->stats.rx_dropped++;
			page_pool_recycle_direct(rx_ring->page_pool, page);
			continue;
		}

		skb_reserve(skb, RX_HEADROOM);
		skb_put(skb, len);
		skb_mark_for_recycle(skb);
		skb->protocol = eth_type_trans(skb, net_dev);

		net_dev->stats.rx_packets++;
		net_dev->stats.rx_bytes += len;

		napi_gro_receive(&rx_ring->napi, skb);
	}

	return packets_processed;
}

static u32 tx_free_slots(const struct xdma_tx_ring *tx_ring)
{
	return (tx_ring->driver_ci + tx_ring->count - tx_ring->driver_pi - 1) %
	       tx_ring->count;
}

static void tx_unmap_desc(struct xdma_tx_ring *tx_ring,
			  struct xdma_tx_buffer_info *bi)
{
	if (bi->is_page)
		dma_unmap_page(tx_ring->dev, bi->dma, bi->dma_len, DMA_TO_DEVICE);
	else
		dma_unmap_single(tx_ring->dev, bi->dma, bi->dma_len, DMA_TO_DEVICE);

	memset(bi, 0, sizeof(*bi));
}

static void tx_fill_desc(struct xdma_tx_ring *tx_ring, u32 idx, dma_addr_t dma,
			 u32 len, bool is_page, bool eop)
{
	struct xdma_tx_buffer_info *bi = &tx_ring->sw_ring[idx];

	bi->dma = dma;
	bi->dma_len = len;
	bi->is_page = is_page;

	tx_xdma_desc_set(tx_ring->hw_desc_ring_virt + idx, dma, len, eop);
}

/* Maps the head and each fragment to its own descriptor. Returns the number
 * of descriptors used, or a negative errno with nothing left mapped.
 */
static int tx_map_skb(struct xdma_tx_ring *tx_ring, struct sk_buff *skb)
{
	u32 nr_frags = skb_shinfo(skb)->nr_frags;
	u32 headlen = skb_headlen(skb);
	u32 idx = tx_ring->driver_pi;
	dma_addr_t dma;
	int used = 0;

	if (headlen) {
		dma = dma_map_single(tx_ring->dev, skb->data, headlen, DMA_TO_DEVICE);
		if (unlikely(dma_mapping_error(tx_ring->dev, dma)))
			return -ENOMEM;

		tx_fill_desc(tx_ring, idx, dma, headlen, false, !nr_frags);
		idx = (idx + 1) % tx_ring->count;
		used++;
	}

	for (u32 i = 0; i < nr_frags; i++) {
		const skb_frag_t *frag = &skb_shinfo(skb)->frags[i];
		u32 frag_len = skb_frag_size(frag);

		dma = skb_frag_dma_map(tx_ring->dev, frag, 0, frag_len, DMA_TO_DEVICE);
		if (unlikely(dma_mapping_error(tx_ring->dev, dma)))
			goto err_unmap;

		tx_fill_desc(tx_ring, idx, dma, frag_len, true, i == nr_frags - 1);
		idx = (idx + 1) % tx_ring->count;
		used++;
	}

	idx = (idx + tx_ring->count - 1) % tx_ring->count;
	tx_ring->sw_ring[idx].skb = skb;

	return used;

err_unmap:
	while (used--) {
		idx = (idx + tx_ring->count - 1) % tx_ring->count;
		tx_unmap_desc(tx_ring, &tx_ring->sw_ring[idx]);
	}
	return -ENOMEM;
}

int tx_clean_skb(struct xdma_tx_ring *tx_ring, int budget)
{
	struct xdma_engine *engine;
	struct engine_regs *regs;
	int packets_processed;
	u32 newly_completed;
	u32 descs_processed;
	u32 *ci;

	ci = &tx_ring->driver_ci;
	engine = tx_ring->h2c_engine;
	regs = engine->regs;

	packets_processed = 0;
	descs_processed = 0;
	spin_lock_bh(&tx_ring->lock);
	newly_completed = read_register(&regs->completed_desc_count) -
			  tx_ring->last_hw_completed;
	while (descs_processed < newly_completed && packets_processed < budget) {
		struct xdma_tx_buffer_info *bi = &tx_ring->sw_ring[*ci];
		struct sk_buff *skb = bi->skb;

		tx_unmap_desc(tx_ring, bi);

		if (skb) {
			dev_kfree_skb_any(skb);
			packets_processed++;
		}

		*ci = (*ci + 1) % tx_ring->count;
		descs_processed++;
	}
	tx_ring->last_hw_completed += descs_processed;
	spin_unlock_bh(&tx_ring->lock);
	return packets_processed;
}

int rx_refill_skb(struct xdma_rx_ring *rx_ring)
{
	struct engine_sgdma_regs *sgdma;
	int packets_processed = 0;
	int rv = 0;
	u32 *ci, *pi;
	u32 w;

	sgdma = rx_ring->c2h_engine->sgdma_regs;
	ci = &rx_ring->driver_ci;
	pi = &rx_ring->driver_pi;

	while (((*pi + 1) % rx_ring->count) != *ci) {
		struct xdma_rx_buffer_info *bi = &rx_ring->sw_ring[*pi];
		struct page *page;

		page = page_pool_dev_alloc_pages(rx_ring->page_pool);
		if (unlikely(!page)) {
			pr_err_ratelimited("Failed to allocate page (idx=%u)\n", *pi);
			rv = -ENOMEM;
			break;
		}

		bi->page = page;
		bi->dma = page_pool_get_dma_addr(page) + RX_HEADROOM;
		rx_xdma_desc_set(rx_ring, *pi, bi->dma, rx_ring->buffer_len);

		*pi = (*pi + 1) % rx_ring->count;
		packets_processed++;
	}

	dma_wmb();
	w = cpu_to_le32(packets_processed);
	dbg_tfr("iowrite32(0x%08x to 0x%p) (credits)\n", w, (void *)&sgdma->credits);
	write_register(w, &sgdma->credits,
		       (unsigned long)&sgdma->credits - (unsigned long)sgdma);

	return rv;
}

int rx_napi_poll(struct napi_struct *napi, int weight)
{
	struct xdma_rx_ring *rx_ring;
	struct engine_regs *regs;
	int packets_processed;
	int rv_refill;

	rx_ring = container_of(napi, struct xdma_rx_ring, napi);
	regs = rx_ring->c2h_engine->regs;

	packets_processed = rx_clean_skb(rx_ring, weight);
	rv_refill = rx_refill_skb(rx_ring);

	/* Stay scheduled so the refill is retried; only a full budget does that. */
	if (rv_refill)
		return weight;

	if (packets_processed < weight) {
		napi_complete_done(napi, packets_processed);
		write_register(XDMA_CTRL_IE_DESC_COMPLETED,
			       &regs->interrupt_enable_mask_w1s,
			       (unsigned long)&regs->interrupt_enable_mask_w1s -
				       (unsigned long)regs);
	}

	return packets_processed;
}

int tx_napi_poll(struct napi_struct *napi, int weight)
{
	struct xdma_tx_ring *tx_ring;
	struct engine_regs *regs;
	int packets_processed;

	tx_ring = container_of(napi, struct xdma_tx_ring, napi);
	regs = tx_ring->h2c_engine->regs;

	packets_processed = tx_clean_skb(tx_ring, weight);

	if (netif_queue_stopped(tx_ring->net_dev) &&
	    tx_free_slots(tx_ring) >= TX_DESC_NEEDED)
		netif_wake_queue(tx_ring->net_dev);

	if (packets_processed < weight) {
		napi_complete_done(napi, packets_processed);

		write_register(XDMA_CTRL_IE_DESC_COMPLETED,
			       &regs->interrupt_enable_mask_w1s,
			       (unsigned long)&regs->interrupt_enable_mask_w1s -
				       (unsigned long)regs);
	}

	return packets_processed;
}

netdev_tx_t eth_xmit_frame(struct sk_buff *skb, struct net_device *net_dev)
{
	struct net_device_priv *xndev;
	struct xdma_engine *engine;
	struct xdma_tx_ring *tx_ring;
	struct engine_sgdma_regs *sgdma;
	struct engine_regs *regs;
	struct net_device_stats *stats = &net_dev->stats;
	int nr_desc;
	int len;

	pr_info_ratelimited("eth_xmit_frame: skb len=%u\n", skb ? skb->len : 0);

	xndev = netdev_priv(net_dev);

	if (unlikely(!xndev)) {
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	tx_ring = xndev->tx_ring;
	if (unlikely(!tx_ring)) {
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	engine = tx_ring->h2c_engine;
	if (unlikely(!engine)) {
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	sgdma = engine->sgdma_regs;
	regs = engine->regs;

	if (skb->len < ETH_ZLEN) {
		if (skb_padto(skb, ETH_ZLEN)) {
			stats->tx_dropped++;
			return NETDEV_TX_OK;
		}
	}

	spin_lock_bh(&tx_ring->lock);

	if (unlikely(tx_free_slots(tx_ring) < skb_shinfo(skb)->nr_frags + 1)) {
		netif_stop_queue(net_dev);
		spin_unlock_bh(&tx_ring->lock);
		return NETDEV_TX_BUSY;
	}

	len = skb->len;

	nr_desc = tx_map_skb(tx_ring, skb);
	if (unlikely(nr_desc < 0)) {
		spin_unlock_bh(&tx_ring->lock);
		stats->tx_dropped++;
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	tx_ring->driver_pi = (tx_ring->driver_pi + nr_desc) % tx_ring->count;
	if (unlikely(tx_free_slots(tx_ring) < TX_DESC_NEEDED))
		netif_stop_queue(net_dev);

	/* Ensure the descriptors are visible to the device before granting credit */
	dma_wmb();

	write_register(cpu_to_le32(nr_desc), &sgdma->credits,
		       (unsigned long)&sgdma->credits - (unsigned long)sgdma);

	{
		u32 st = read_register(&regs->status);
		u32 ctrl = read_register(&regs->control);
		u32 cc = read_register(&regs->completed_desc_count);
		struct xdma_engine *rxe = xndev->rx_ring ? xndev->rx_ring->c2h_engine : NULL;
		struct engine_regs *rregs = rxe ? rxe->regs : NULL;
		u32 rst = rregs ? read_register(&rregs->status) : 0;
		u32 rctrl = rregs ? read_register(&rregs->control) : 0;
		u32 rcc = rregs ? read_register(&rregs->completed_desc_count) : 0;
		pr_info_ratelimited("h2c: st=0x%08x ctl=0x%08x cmpl=%u pi=%u ci=%u | c2h: st=0x%08x ctl=0x%08x cmpl=%u\n",
				    st, ctrl, cc, tx_ring->driver_pi, tx_ring->driver_ci,
				    rst, rctrl, rcc);
	}

	spin_unlock_bh(&tx_ring->lock);

	netif_trans_update(net_dev);
	stats->tx_packets++;
	stats->tx_bytes += len;

	return NETDEV_TX_OK;
}

static int eth_up(struct net_device_priv *xndev)
{
	int rv;

	rv = configure_rx(xndev);
	if (rv) {
		pr_err("Failed to configure rx ring");
		return rv;
	}

	rv = configure_tx(xndev);
	if (rv) {
		pr_err("Failed to configure tx ring");
		return rv;
	}

	netif_start_queue(xndev->net_dev);
	return 0;
}

static int eth_open(struct net_device *net_dev)
{
	struct net_device_priv *xndev;
	int rv;

	xndev = netdev_priv(net_dev);
	if (!xndev) {
		pr_info("net_dev 0x%p no valid net_device_priv.\n", net_dev);
		return -EINVAL;
	}

	netif_carrier_off(net_dev);
	if ((rv = eth_up(xndev))) {
		netdev_err(net_dev, "Cannot open interface, aborting\n");
		return rv;
	}
	netif_carrier_on(net_dev);
	return 0;
}

static int eth_close(struct net_device *net_dev)
{
	struct net_device_priv *xndev = netdev_priv(net_dev);
	struct xdma_rx_ring *rx_ring;
	struct xdma_tx_ring *tx_ring;

	if (!xndev)
		return -EINVAL;

	netif_carrier_off(net_dev);
	netif_tx_disable(net_dev);

	tx_ring = xndev->tx_ring;
	rx_ring = xndev->rx_ring;

	if (tx_ring && tx_ring->h2c_engine) {
		stop_tx_sgdma(tx_ring);
		free_irq(tx_ring->h2c_engine->msix_irq_line, xndev);
		napi_disable(&tx_ring->napi);

		spin_lock_bh(&tx_ring->lock);
		u32 ci = tx_ring->driver_ci;
		u32 pi = tx_ring->driver_pi;
		while (ci != pi) {
			struct xdma_tx_buffer_info *bi = &tx_ring->sw_ring[ci];
			struct sk_buff *skb = bi->skb;

			tx_unmap_desc(tx_ring, bi);
			if (skb)
				dev_kfree_skb_any(skb);
			ci = (ci + 1) % tx_ring->count;
		}
		memset(tx_ring->hw_desc_ring_virt, 0,
		       sizeof(*tx_ring->hw_desc_ring_virt) * tx_ring->count);
		memset(tx_ring->sw_ring, 0,
		       sizeof(*tx_ring->sw_ring) * tx_ring->count);
		tx_ring->driver_pi = 0;
		tx_ring->driver_ci = 0;
		tx_ring->last_hw_completed = 0;
		spin_unlock_bh(&tx_ring->lock);
	}

	if (rx_ring && rx_ring->c2h_engine) {
		stop_rx_sgdma(rx_ring);
		free_irq(rx_ring->c2h_engine->msix_irq_line, xndev);
		napi_disable(&rx_ring->napi);

		free_rx_pages(rx_ring);
		memset(rx_ring->hw_res_ring_virt, 0,
		       sizeof(*rx_ring->hw_res_ring_virt) * rx_ring->count);
		rx_ring->driver_pi = 0;
		rx_ring->driver_ci = 0;
	}
	return 0;
}

const struct net_device_ops netdev_ops = {
	.ndo_open       = eth_open,
	.ndo_stop       = eth_close,
	.ndo_start_xmit = eth_xmit_frame,
};
