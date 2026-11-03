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
		int len;

		if (!res->status)
			break;

		dma_rmb();
		res->status = 0;

		dma_unmap_single(rx_ring->dev, bi->sk_buff_phys, rx_ring->buffer_len,
				 DMA_FROM_DEVICE);

		len = le32_to_cpu(res->length);
		skb_put(bi->skb, len);
		bi->skb->protocol = eth_type_trans(bi->skb, net_dev);
		napi_gro_receive(&rx_ring->napi, bi->skb);

		bi->skb = NULL;
		bi->sk_buff_phys = 0;

		*ci = (*ci + 1) % rx_ring->count;
	}

	return packets_processed;
}

int tx_clean_skb(struct xdma_tx_ring *tx_ring)
{
	struct xdma_engine *engine;
	struct engine_regs *regs;
	int packets_processed;
	u32 newly_completed;
	u32 *ci;

	ci = &tx_ring->driver_ci;
	engine = tx_ring->h2c_engine;
	regs = engine->regs;

	packets_processed = 0;
	spin_lock_bh(&tx_ring->lock);
	newly_completed = read_register(&regs->completed_desc_count) -
			  tx_ring->last_hw_completed;
	while ((u32)packets_processed < newly_completed) {
		struct xdma_tx_buffer_info *bi = &tx_ring->sw_ring[*ci];

		if (bi->skb) {
			dma_unmap_single(tx_ring->dev, bi->sk_buff_phys, bi->dma_len,
					 DMA_TO_DEVICE);
			dev_kfree_skb_any(bi->skb);
		}

		bi->skb = NULL;
		bi->sk_buff_phys = 0;
		bi->dma_len = 0;

		*ci = (*ci + 1) % tx_ring->count;
		packets_processed++;
	}
	tx_ring->last_hw_completed += packets_processed;
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
		dma_addr_t sk_buff_phys;

		bi->skb = napi_alloc_skb(&rx_ring->napi, rx_ring->buffer_len);
		if (unlikely(!bi->skb)) {
			pr_err("Failed to allocate sk_buff (idx=%u)\n", *pi);
			rv = -ENOMEM;
			break;
		}

		sk_buff_phys = dma_map_single(rx_ring->dev, bi->skb->data,
					      rx_ring->buffer_len, DMA_FROM_DEVICE);
		if (unlikely(dma_mapping_error(rx_ring->dev, sk_buff_phys))) {
			dev_kfree_skb_any(bi->skb);
			pr_err("Failed map sk_buff to dma addr (idx=%u)\n", *pi);
			rv = -ENOMEM;
			break;
		}

		bi->sk_buff_phys = sk_buff_phys;
		rx_xdma_desc_set(rx_ring, *pi, sk_buff_phys, rx_ring->buffer_len);

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

	packets_processed = rx_clean_skb(rx_ring, MAX_NAPI_PACKETS_PER_CALL);
	rv_refill = rx_refill_skb(rx_ring);

	if (packets_processed < MAX_NAPI_PACKETS_PER_CALL && !rv_refill) {
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

	packets_processed = tx_clean_skb(tx_ring);

	if (packets_processed < MAX_NAPI_PACKETS_PER_CALL) {
		napi_complete_done(napi, packets_processed);

		if (netif_queue_stopped(tx_ring->net_dev))
			netif_wake_queue(tx_ring->net_dev);

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
	u32 ring_size;
	u32 *pi;
	int len;
	dma_addr_t dma;

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

	if (skb_is_nonlinear(skb)) {
		if (skb_linearize(skb)) {
			stats->tx_dropped++;
			dev_kfree_skb_any(skb);
			return NETDEV_TX_OK;
		}
	}

	spin_lock_bh(&tx_ring->lock);

	ring_size = tx_ring->count;
	pi = &tx_ring->driver_pi;
	if (unlikely((*pi + 1) % ring_size == tx_ring->driver_ci)) {
		netif_stop_queue(net_dev);
		spin_unlock_bh(&tx_ring->lock);
		return NETDEV_TX_BUSY;
	}

	len = skb->len;

	dma = dma_map_single(tx_ring->dev, skb->data, len, DMA_TO_DEVICE);
	if (unlikely(dma_mapping_error(tx_ring->dev, dma))) {
		spin_unlock_bh(&tx_ring->lock);
		stats->tx_dropped++;
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	struct xdma_tx_buffer_info *bi = &tx_ring->sw_ring[*pi];
	bi->skb = skb;
	bi->sk_buff_phys = dma;
	bi->dma_len = len;

	tx_xdma_desc_set(tx_ring->hw_desc_ring_virt + *pi, dma, len);

	*pi = (*pi + 1) % ring_size;
	if (unlikely((*pi + 1) % ring_size == tx_ring->driver_ci))
		netif_stop_queue(net_dev);

	/* Ensure the descriptor is visible to the device before granting credit */
	dma_wmb();

	write_register(cpu_to_le32(1), &sgdma->credits,
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
			WARN_ON_ONCE(!bi->skb);
			if (bi->skb) {
				dma_unmap_single(tx_ring->dev, bi->sk_buff_phys,
						 bi->dma_len, DMA_TO_DEVICE);
				dev_kfree_skb_any(bi->skb);
			}
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

		free_rx_sk_buff(rx_ring);
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
