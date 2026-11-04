#define pr_fmt(fmt) KBUILD_MODNAME ":%s: " fmt, __func__

#include "eth_mod.h"

static int wr_sgdma_desc_regs_tx(struct xdma_tx_ring *tx_ring) {
	struct xdma_engine *engine;
	struct engine_sgdma_regs *sgdma;
	u32 w;

	engine = tx_ring->h2c_engine;
	if (!engine) {
		pr_err("tx dma engine NULL\n");
		return -EINVAL;
	}

	// Wire descriptors as a circular ring (control=0; credit mode gates fetch)
	for (u32 i = 0; i < tx_ring->count; i++) {
		u32 next_idx = (i + 1) % tx_ring->count;
		dma_addr_t next_phys =
			tx_ring->hw_desc_ring_phys + (dma_addr_t)next_idx * sizeof(*tx_ring->hw_desc_ring_virt);
		tx_ring->hw_desc_ring_virt[i].next_lo = cpu_to_le32(PCI_DMA_L(next_phys));
		tx_ring->hw_desc_ring_virt[i].next_hi = cpu_to_le32(PCI_DMA_H(next_phys));
		tx_ring->hw_desc_ring_virt[i].control = 0;
	}
	tx_ring->last_hw_completed = 0;

	sgdma = engine->sgdma_regs;

	// Point engine at the start of the ring (engine is not started yet)
	w = cpu_to_le32(PCI_DMA_L(tx_ring->hw_desc_ring_phys));
	dbg_tfr("iowrite32(0x%08x to 0x%p) (first_desc_lo)\n", w, (void *)&sgdma->first_desc_lo);
	write_register(w, &sgdma->first_desc_lo, (unsigned long)&sgdma->first_desc_lo - (unsigned long)sgdma);

	w = cpu_to_le32(PCI_DMA_H(tx_ring->hw_desc_ring_phys));
	dbg_tfr("iowrite32(0x%08x to 0x%p) (first_desc_hi)\n", w, (void *)&sgdma->first_desc_hi);
	write_register(w, &sgdma->first_desc_hi, (unsigned long)&sgdma->first_desc_hi - (unsigned long)sgdma);

	// No pre-fetch: engine fetches one descriptor at a time via next pointers
	dbg_tfr("iowrite32(0x%08x to 0x%p) (first_desc_adjacent)\n", 0, (void *)&sgdma->first_desc_adjacent);
	write_register(0, &sgdma->first_desc_adjacent,
		       (unsigned long)&sgdma->first_desc_adjacent - (unsigned long)sgdma);

	w = read_register(&engine->regs->status);
	dbg_tfr("ioread32(0x%p) = 0x%08x (dummy read flushes writes).\n", &engine->regs->status, w);
	return 0;
}

void tx_xdma_desc_set(struct xdma_desc *hw_desc_ring_virt, dma_addr_t dma, int len, bool eop) {
	// Magic required by hardware; EOP asserts tlast; COMPLETED requests IRQ
	hw_desc_ring_virt->control = cpu_to_le32(DESC_MAGIC | (eop ? XDMA_DESC_EOP : 0) | XDMA_DESC_COMPLETED);
	hw_desc_ring_virt->bytes = cpu_to_le32(len);

	hw_desc_ring_virt->src_addr_lo = cpu_to_le32(PCI_DMA_L(dma));
	hw_desc_ring_virt->src_addr_hi = cpu_to_le32(PCI_DMA_H(dma));

	// FIFO beginning on card
	hw_desc_ring_virt->dst_addr_lo = cpu_to_le32(PCI_DMA_L(0));
	hw_desc_ring_virt->dst_addr_hi = cpu_to_le32(PCI_DMA_H(0));

	// next_lo/next_hi pre-wired as a ring during init; do not touch here
}

static int start_tx_sgdma(struct xdma_tx_ring *tx_ring) {
	struct xdma_engine *engine;
	struct engine_regs *regs;
	u32 w;

	engine = tx_ring->h2c_engine;
	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	regs = engine->regs;

	write_register(XDMA_CTRL_IE_DESC_COMPLETED, &regs->interrupt_enable_mask_w1s,
		       (unsigned long)&regs->interrupt_enable_mask_w1s - (unsigned long)regs);

	write_register(XDMA_CTRL_RUN_AND_IE, &regs->control_w1s,
		       (unsigned long)&regs->control_w1s - (unsigned long)regs);

	// Flush posted writes
	w = read_register(&regs->status);

	return 0;
}

int stop_tx_sgdma(struct xdma_tx_ring *tx_ring) {
	struct xdma_engine *engine;
	struct engine_regs *regs;
	u32 w;
	int timeout = SGDMA_TIMEOUT;

	engine = tx_ring->h2c_engine;
	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	regs = engine->regs;

	netif_stop_queue(tx_ring->net_dev);

	write_register(XDMA_CTRL_IE_DESC_COMPLETED, &regs->interrupt_enable_mask_w1c,
		       (unsigned long)&regs->interrupt_enable_mask_w1c - (unsigned long)regs);

	write_register(XDMA_CTRL_RUN_STOP, &regs->control_w1c, (unsigned long)&regs->control_w1c - (unsigned long)regs);

	w = read_register(&regs->status);
	while ((w & XDMA_STAT_BUSY) && timeout--) {
		mdelay(1);
		w = read_register(&regs->status);
	}

	if (w & XDMA_STAT_BUSY) {
		pr_err("failed to stop H2C engine. status=0x%08x\n", w);
		return -EIO;
	}

	return 0;
}

int tx_ring_init(struct net_device_priv *xndev) {
	struct xdma_tx_ring *tx_ring;
	struct xdma_dev *xdev;
	struct xdma_engine *h2c_engine;
	size_t hw_desc_ring_size;
	size_t hw_wb_compl_size;
	size_t sw_ring_size;

	tx_ring = kzalloc(sizeof(*tx_ring), GFP_KERNEL);
	if (!tx_ring) {
		pr_err("Failed to allocate tx_ring struct\n");
		return -ENOMEM;
	}

	xndev->tx_ring = tx_ring;
	xdev = xndev->xdev;

	h2c_engine = &xdev->engine_h2c[0];
	tx_ring->h2c_engine = h2c_engine;

	tx_ring->dev = &xdev->pdev->dev;
	tx_ring->net_dev = xndev->net_dev;

	tx_ring->count = h2c_engine->desc_max;

	tx_ring->driver_pi = 0;
	tx_ring->driver_ci = 0;

	spin_lock_init(&tx_ring->lock);

	hw_desc_ring_size = sizeof(*tx_ring->hw_desc_ring_virt) * tx_ring->count;
	tx_ring->hw_desc_ring_virt =
		dma_alloc_coherent(tx_ring->dev, hw_desc_ring_size, &tx_ring->hw_desc_ring_phys, GFP_KERNEL);
	if (!tx_ring->hw_desc_ring_virt) {
		pr_err("Failed to allocate TX HW descriptor ring (size=%zu)\n", hw_desc_ring_size);
		goto err_hw_desc_ring;
	}

	hw_wb_compl_size = sizeof(*tx_ring->hw_wb_compl_virt);
	tx_ring->hw_wb_compl_virt =
		dma_alloc_coherent(tx_ring->dev, hw_wb_compl_size, &tx_ring->hw_wb_compl_phys, GFP_KERNEL);
	if (!tx_ring->hw_wb_compl_virt) {
		pr_err("Failed to allocate WB addr for tx (size=%zu)\n", hw_wb_compl_size);
		goto err_wb_compl;
	}

	sw_ring_size = sizeof(*tx_ring->sw_ring) * tx_ring->count;
	tx_ring->sw_ring = kzalloc(sw_ring_size, GFP_KERNEL);
	if (!tx_ring->sw_ring) {
		pr_err("Failed to allocate TX SW ring (size=%zu)\n", sw_ring_size);
		goto err_sw_ring;
	}

	netif_napi_add(tx_ring->net_dev, &tx_ring->napi, tx_napi_poll);
	return 0;

err_sw_ring:
	dma_free_coherent(tx_ring->dev, hw_wb_compl_size, tx_ring->hw_wb_compl_virt, tx_ring->hw_wb_compl_phys);
err_wb_compl:
	dma_free_coherent(tx_ring->dev, hw_desc_ring_size, tx_ring->hw_desc_ring_virt, tx_ring->hw_desc_ring_phys);
err_hw_desc_ring:
	kfree(tx_ring);
	xndev->tx_ring = NULL;
	return -ENOMEM;
}

void tx_ring_free(struct net_device_priv *xndev) {
	struct xdma_tx_ring *tx_ring;
	struct xdma_engine *h2c_engine;
	size_t hw_desc_ring_size;
	size_t hw_wb_compl_size;

	tx_ring = xndev->tx_ring;
	if (!tx_ring)
		return;

	h2c_engine = tx_ring->h2c_engine;

	netif_napi_del(&tx_ring->napi);

	kfree(tx_ring->sw_ring);

	hw_desc_ring_size = sizeof(*tx_ring->hw_desc_ring_virt) * h2c_engine->desc_max;
	dma_free_coherent(tx_ring->dev, hw_desc_ring_size, tx_ring->hw_desc_ring_virt, tx_ring->hw_desc_ring_phys);

	hw_wb_compl_size = sizeof(*tx_ring->hw_wb_compl_virt);
	dma_free_coherent(tx_ring->dev, hw_wb_compl_size, tx_ring->hw_wb_compl_virt, tx_ring->hw_wb_compl_phys);

	kfree(tx_ring);
	xndev->tx_ring = NULL;
}

static irqreturn_t tx_irq_handler(int irq, void *dev_id) {
	struct net_device_priv *xndev;
	struct xdma_tx_ring *tx_ring;
	struct xdma_engine *engine;
	struct engine_regs *regs;

	xndev = (struct net_device_priv *)(dev_id);
	tx_ring = xndev->tx_ring;
	if (unlikely(!tx_ring))
		return IRQ_NONE;

	engine = tx_ring->h2c_engine;
	if (unlikely(!engine))
		return IRQ_NONE;

	regs = engine->regs;

	write_register(XDMA_CTRL_IE_DESC_COMPLETED, &regs->interrupt_enable_mask_w1c,
		       (unsigned long)&regs->interrupt_enable_mask_w1c - (unsigned long)regs);

	// W1C status.descriptor_completed to re-arm the MSI-X edge.
	write_register(XDMA_CTRL_IE_DESC_COMPLETED, &regs->status, (unsigned long)&regs->status - (unsigned long)regs);
	// Flush the clear so a completion after NAPI's ring check is not wiped.
	read_register(&regs->status);

	napi_schedule(&tx_ring->napi);
	return IRQ_HANDLED;
}

int configure_tx(struct net_device_priv *xndev) {
	int rv;
	struct xdma_tx_ring *tx_ring;
	struct xdma_engine *h2c_engine;

	tx_ring = xndev->tx_ring;
	if (!tx_ring) {
		pr_info("xndev 0x%p no valid tx_ring.\n", xndev);
		return -EINVAL;
	}

	h2c_engine = tx_ring->h2c_engine;
	if (!h2c_engine) {
		pr_info("tx_ring 0x%p no valid h2c_engine.\n", tx_ring);
		return -EINVAL;
	}

	if ((rv = wr_sgdma_desc_regs_tx(tx_ring)))
		goto err_wr_desc_regs;

	napi_enable(&tx_ring->napi);

	rv = request_irq(h2c_engine->msix_irq_line, tx_irq_handler, 0, xndev->net_dev->name, xndev);
	if (rv) {
		pr_info("failed to request irq.\n");
		goto err_request_irq;
	}

	if ((rv = start_tx_sgdma(tx_ring)))
		goto err_start_sgdma;

	return 0;

err_start_sgdma:
	free_irq(h2c_engine->msix_irq_line, xndev);
err_request_irq:
	napi_disable(&tx_ring->napi);
err_wr_desc_regs:
	return rv;
}
