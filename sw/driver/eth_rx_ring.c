#define pr_fmt(fmt) KBUILD_MODNAME ":%s: " fmt, __func__

#include "eth_mod.h"

int wr_sgdma_desc_regs_rx(struct xdma_rx_ring *rx_ring)
{
	struct xdma_engine *engine;
	struct engine_sgdma_regs *sgdma;
	u32 w;

	engine = rx_ring->c2h_engine;
	if (!engine) {
		pr_err("rx dma engine NULL\n");
		return -EINVAL;
	}

	sgdma = engine->sgdma_regs;

	w = cpu_to_le32(PCI_DMA_L(rx_ring->hw_desc_ring_phys));
	dbg_tfr("iowrite32(0x%08x to 0x%p) (first_desc_lo)\n", w, (void *)&sgdma->first_desc_lo);
	write_register(w, &sgdma->first_desc_lo,
		       (unsigned long)&sgdma->first_desc_lo - (unsigned long)sgdma);

	w = cpu_to_le32(PCI_DMA_H(rx_ring->hw_desc_ring_phys));
	dbg_tfr("iowrite32(0x%08x to 0x%p) (first_desc_hi)\n", w, (void *)&sgdma->first_desc_hi);
	write_register(w, &sgdma->first_desc_hi,
		       (unsigned long)&sgdma->first_desc_hi - (unsigned long)sgdma);

	dbg_tfr("iowrite32(0x%08x to 0x%p) (first_desc_adjacent)\n", 0, (void *)&sgdma->first_desc_adjacent);
	write_register(0, &sgdma->first_desc_adjacent,
		       (unsigned long)&sgdma->first_desc_adjacent - (unsigned long)sgdma);

	/* Clamp initial grant: desc_max can exceed the 10-bit credit field. */
	w = cpu_to_le32(min_t(u32, rx_ring->count, XDMA_C2H_CREDIT_MAX));
	pr_info("rx_ring->count=%u, granting initial credits=%u\n",
		rx_ring->count, le32_to_cpu(w));
	dbg_tfr("iowrite32(0x%08x to 0x%p) (credits)\n", w, (void *)&sgdma->credits);
	write_register(w, &sgdma->credits,
		       (unsigned long)&sgdma->credits - (unsigned long)sgdma);

	w = read_register(&engine->regs->status);
	dbg_tfr("ioread32(0x%p) = 0x%08x (dummy read flushes writes).\n",
		&engine->regs->status, w);

	return 0;
}

void rx_xdma_desc_set(struct xdma_rx_ring *rx_ring, u32 idx,
		      dma_addr_t dma, int len)
{
	struct xdma_desc *desc = rx_ring->hw_desc_ring_virt + idx;
	/* src_addr is the result writeback address for C2H, not a data source. */
	dma_addr_t wb_phys = rx_ring->hw_res_ring_phys +
			     (dma_addr_t)idx * sizeof(*rx_ring->hw_res_ring_virt);
	u32 next_idx = (idx + 1) % rx_ring->count;
	dma_addr_t next_phys = rx_ring->hw_desc_ring_phys +
			       (dma_addr_t)next_idx * sizeof(*rx_ring->hw_desc_ring_virt);

	desc->control = cpu_to_le32(DESC_MAGIC | XDMA_DESC_COMPLETED);
	desc->bytes = cpu_to_le32(len);

	desc->src_addr_lo = cpu_to_le32(PCI_DMA_L(wb_phys));
	desc->src_addr_hi = cpu_to_le32(PCI_DMA_H(wb_phys));

	desc->dst_addr_lo = cpu_to_le32(PCI_DMA_L(dma));
	desc->dst_addr_hi = cpu_to_le32(PCI_DMA_H(dma));

	desc->next_lo = cpu_to_le32(PCI_DMA_L(next_phys));
	desc->next_hi = cpu_to_le32(PCI_DMA_H(next_phys));
}

int start_rx_sgdma(struct xdma_rx_ring *rx_ring)
{
	struct xdma_engine *engine;
	struct engine_regs *regs;
	u32 w;
	int timeout = SGDMA_TIMEOUT;

	engine = rx_ring->c2h_engine;
	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	regs = engine->regs;

	write_register(XDMA_CTRL_IE_DESC_COMPLETED,
		       &regs->interrupt_enable_mask_w1s,
		       (unsigned long)&regs->interrupt_enable_mask_w1s -
			       (unsigned long)regs);

	write_register(XDMA_CTRL_RUN_AND_IE, &regs->control_w1s,
		       (unsigned long)&regs->control_w1s - (unsigned long)regs);

	w = read_register(&regs->status);
	while (!(w & XDMA_STAT_BUSY) && timeout--) {
		mdelay(1);
		w = read_register(&regs->status);
	}

	if (!(w & XDMA_STAT_BUSY)) {
		pr_err("failed to start C2H engine. status=0x%08x\n", w);
		return -EIO;
	}

	return 0;
}

int stop_rx_sgdma(struct xdma_rx_ring *rx_ring)
{
	struct xdma_engine *engine;
	struct engine_regs *regs;
	u32 w;
	int timeout = SGDMA_TIMEOUT;

	engine = rx_ring->c2h_engine;
	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	regs = engine->regs;

	write_register(XDMA_CTRL_RUN_STOP, &regs->control_w1c,
		       (unsigned long)&regs->control_w1c - (unsigned long)regs);

	write_register(XDMA_CTRL_IE_DESC_COMPLETED,
		       &regs->interrupt_enable_mask_w1c,
		       (unsigned long)&regs->interrupt_enable_mask_w1c - (unsigned long)regs);

	w = read_register(&regs->status);
	while ((w & XDMA_STAT_BUSY) && timeout--) {
		mdelay(1);
		w = read_register(&regs->status);
	}

	if (w & XDMA_STAT_BUSY) {
		pr_err("failed to stop C2H engine. status=0x%08x\n", w);
		return -EIO;
	}

	return 0;
}

int rx_ring_init(struct net_device_priv *xndev)
{
	struct xdma_rx_ring *rx_ring;
	struct xdma_dev *xdev;
	struct xdma_engine *c2h_engine;
	size_t hw_desc_ring_size;
	size_t hw_res_ring_size;
	size_t sw_ring_size;

	rx_ring = kzalloc(sizeof(*rx_ring), GFP_KERNEL);
	if (!rx_ring) {
		pr_err("Failed to allocate rx_ring struct\n");
		return -ENOMEM;
	}

	xndev->rx_ring = rx_ring;
	xdev = xndev->xdev;

	c2h_engine = &xdev->engine_c2h[0];
	rx_ring->c2h_engine = c2h_engine;

	rx_ring->count = c2h_engine->desc_max;
	rx_ring->dev = &xdev->pdev->dev;
	rx_ring->net_dev = xndev->net_dev;
	rx_ring->buffer_len = RX_BUFFER_LEN;

	hw_desc_ring_size = sizeof(*rx_ring->hw_desc_ring_virt) * c2h_engine->desc_max;
	hw_res_ring_size  = sizeof(*rx_ring->hw_res_ring_virt) * c2h_engine->desc_max;
	sw_ring_size      = sizeof(*rx_ring->sw_ring) * c2h_engine->desc_max;

	rx_ring->hw_desc_ring_virt = dma_alloc_coherent(
		rx_ring->dev, hw_desc_ring_size, &rx_ring->hw_desc_ring_phys, GFP_KERNEL);
	if (!rx_ring->hw_desc_ring_virt) {
		pr_err("Failed to allocate HW descriptor ring (size=%zu)\n",
		       hw_desc_ring_size);
		goto err_hw_desc_ring;
	}

	rx_ring->hw_res_ring_virt = dma_alloc_coherent(
		rx_ring->dev, hw_res_ring_size, &rx_ring->hw_res_ring_phys, GFP_KERNEL);
	if (!rx_ring->hw_res_ring_virt) {
		pr_err("Failed to allocate HW response ring (size=%zu)\n",
		       hw_res_ring_size);
		goto err_hw_res_ring;
	}
	memset(rx_ring->hw_res_ring_virt, 0, hw_res_ring_size);

	rx_ring->sw_ring = kzalloc(sw_ring_size, GFP_KERNEL);
	if (!rx_ring->sw_ring) {
		pr_err("Failed to allocate SW ring (size=%zu)\n", sw_ring_size);
		goto err_sw_ring;
	}

	netif_napi_add(rx_ring->net_dev, &rx_ring->napi, rx_napi_poll);

	return 0;

err_sw_ring:
	dma_free_coherent(rx_ring->dev, hw_res_ring_size, rx_ring->hw_res_ring_virt,
			  rx_ring->hw_res_ring_phys);
err_hw_res_ring:
	dma_free_coherent(rx_ring->dev, hw_desc_ring_size, rx_ring->hw_desc_ring_virt,
			  rx_ring->hw_desc_ring_phys);
err_hw_desc_ring:
	kfree(rx_ring);
	return -ENOMEM;
}

void rx_ring_free(struct net_device_priv *xndev)
{
	struct xdma_rx_ring *rx_ring;
	struct xdma_engine *c2h_engine;
	size_t hw_desc_ring_size;
	size_t hw_res_ring_size;

	rx_ring = xndev->rx_ring;
	if (!rx_ring)
		return;

	c2h_engine = rx_ring->c2h_engine;

	hw_desc_ring_size =
		sizeof(*rx_ring->hw_desc_ring_virt) * c2h_engine->desc_max;
	hw_res_ring_size =
		sizeof(*rx_ring->hw_res_ring_virt) * c2h_engine->desc_max;

	netif_napi_del(&rx_ring->napi);

	kfree(rx_ring->sw_ring);

	dma_free_coherent(rx_ring->dev, hw_res_ring_size, rx_ring->hw_res_ring_virt,
			  rx_ring->hw_res_ring_phys);

	dma_free_coherent(rx_ring->dev, hw_desc_ring_size, rx_ring->hw_desc_ring_virt,
			  rx_ring->hw_desc_ring_phys);

	kfree(rx_ring);
	xndev->rx_ring = NULL;
}

static int rx_page_pool_create(struct xdma_rx_ring *rx_ring)
{
	struct page_pool_params params = {
		.flags = PP_FLAG_DMA_MAP | PP_FLAG_DMA_SYNC_DEV,
		.order = 0,
		.pool_size = rx_ring->count,
		.nid = dev_to_node(rx_ring->dev),
		.dev = rx_ring->dev,
		.napi = &rx_ring->napi,
		.dma_dir = DMA_FROM_DEVICE,
		.offset = RX_HEADROOM,
		.max_len = rx_ring->buffer_len,
	};
	struct page_pool *pool;

	pool = page_pool_create(&params);
	if (IS_ERR(pool))
		return PTR_ERR(pool);

	rx_ring->page_pool = pool;
	return 0;
}

int alloc_rx_pages(struct xdma_rx_ring *rx_ring)
{
	size_t buff_idx;
	int rv;

	/* build_skb needs the headroom and shared info around the frame. */
	BUILD_BUG_ON(RX_HEADROOM + RX_BUFFER_LEN +
		     SKB_DATA_ALIGN(sizeof(struct skb_shared_info)) > PAGE_SIZE);

	rv = rx_page_pool_create(rx_ring);
	if (rv) {
		pr_err("Failed to create page_pool: %d\n", rv);
		return rv;
	}

	for (buff_idx = 0; buff_idx < rx_ring->count; buff_idx++) {
		struct xdma_rx_buffer_info *bi = &rx_ring->sw_ring[buff_idx];
		struct page *page;

		page = page_pool_alloc_pages(rx_ring->page_pool, GFP_KERNEL);
		if (unlikely(!page)) {
			pr_err("Failed to allocate page (idx=%zu)\n", buff_idx);
			free_rx_pages(rx_ring);
			return -ENOMEM;
		}

		bi->page = page;
		bi->dma = page_pool_get_dma_addr(page) + RX_HEADROOM;

		rx_xdma_desc_set(rx_ring, buff_idx, bi->dma, rx_ring->buffer_len);
	}

	rx_ring->driver_ci = 0;
	rx_ring->driver_pi = 0;
	dma_wmb();

	return 0;
}

void free_rx_pages(struct xdma_rx_ring *rx_ring)
{
	if (!rx_ring->page_pool)
		return;

	for (size_t i = 0; i < rx_ring->count; i++) {
		struct xdma_rx_buffer_info *bi = &rx_ring->sw_ring[i];

		if (bi->page)
			page_pool_put_full_page(rx_ring->page_pool, bi->page, false);
		bi->page = NULL;
		bi->dma = 0;
	}

	page_pool_destroy(rx_ring->page_pool);
	rx_ring->page_pool = NULL;
}

static irqreturn_t rx_irq_handler(int irq, void *dev_id)
{
	u32 w;
	struct net_device_priv *xndev;
	struct xdma_rx_ring *rx_ring;
	struct xdma_engine *engine;
	struct engine_regs *regs;

	pr_info_ratelimited("rx_irq_handler fired irq=%d\n", irq);

	xndev = (struct net_device_priv *)dev_id;
	rx_ring = xndev->rx_ring;
	if (unlikely(!rx_ring))
		return IRQ_NONE;

	engine = rx_ring->c2h_engine;
	if (unlikely(!engine))
		return IRQ_NONE;

	regs = engine->regs;

	write_register(XDMA_CTRL_IE_DESC_COMPLETED,
		       &regs->interrupt_enable_mask_w1c,
		       (unsigned long)&regs->interrupt_enable_mask_w1c - (unsigned long)regs);

	/* W1C status.descriptor_completed to re-arm the MSI-X edge. */
	write_register(XDMA_CTRL_IE_DESC_COMPLETED, &regs->status,
		       (unsigned long)&regs->status - (unsigned long)regs);
	w = read_register(&regs->status);
	dbg_tfr("status after W1C clear = 0x%08x\n", w);

	napi_schedule(&rx_ring->napi);

	return IRQ_HANDLED;
}

int configure_rx(struct net_device_priv *xndev)
{
	int rv;
	struct xdma_rx_ring *rx_ring;
	struct xdma_engine *c2h_engine;

	rx_ring = xndev->rx_ring;
	if (!rx_ring) {
		pr_info("xndev 0x%p no valid rx_ring.\n", xndev);
		return -EINVAL;
	}

	c2h_engine = rx_ring->c2h_engine;
	if (!c2h_engine) {
		pr_info("rx_ring 0x%p no valid c2h_engine.\n", rx_ring);
		return -EINVAL;
	}

	if ((rv = alloc_rx_pages(rx_ring)))
		return rv;

	if ((rv = wr_sgdma_desc_regs_rx(rx_ring)))
		goto err_wr_desc_regs;

	napi_enable(&rx_ring->napi);

	rv = request_irq(c2h_engine->msix_irq_line, rx_irq_handler, 0,
			 xndev->net_dev->name, xndev);
	if (rv) {
		pr_info("failed to request irq.\n");
		goto err_request_irq;
	}

	if ((rv = start_rx_sgdma(rx_ring)))
		goto err_start_sgdma;

	return 0;

err_start_sgdma:
	free_irq(c2h_engine->msix_irq_line, xndev);
err_request_irq:
	napi_disable(&rx_ring->napi);
err_wr_desc_regs:
	free_rx_pages(rx_ring);
	return rv;
}
