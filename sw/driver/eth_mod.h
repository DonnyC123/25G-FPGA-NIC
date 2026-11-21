
#ifndef __ETH_MODULE_H__
#define __ETH_MODULE_H__

#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/netdevice.h>
#include <linux/pci.h>
#include <linux/slab.h>
#include <linux/spinlock.h>

#include <net/page_pool/helpers.h>

#include "libxdma.h"
#include "xdma_thread.h"

#ifdef __LIBXDMA_DEBUG__
#define write_register(v, mem, off) __write_register(__func__, v, mem, off)
#else
#define write_register(v, mem, off) iowrite32(v, mem)
#endif

#define XDMA_CTRL_RUN_AND_IE                                                                         \
	(XDMA_CTRL_RUN_STOP | XDMA_CTRL_IE_DESC_STOPPED | XDMA_CTRL_IE_DESC_COMPLETED |              \
	 XDMA_CTRL_IE_DESC_ALIGN_MISMATCH | XDMA_CTRL_IE_MAGIC_STOPPED | XDMA_CTRL_IE_IDLE_STOPPED | \
	 XDMA_CTRL_IE_READ_ERROR | XDMA_CTRL_IE_DESC_ERROR)

#define ETH_MAX_PORTS	   2
#define WATCHDOG_PERIOD	   (5 * HZ)
#define RX_BUFFER_LEN	   2048
#define RX_HEADROOM	   NET_SKB_PAD
#define TX_DESC_NEEDED	   (MAX_SKB_FRAGS + 2)
#define SGDMA_TIMEOUT	   50
#define XDMA_CREDIT_MAX	   1023
#define XDMA_WB_COUNT_MASK 0xFFFFFF
#define TX_FEATURES	   (NETIF_F_HW_CSUM | NETIF_F_SG)
#define ETH_TX_META_CSUM   BIT(0)

#define ETH_RX_HASH_NONE 0
#define ETH_RX_HASH_L3	 1
#define ETH_RX_HASH_L4	 2

struct eth_rx_meta {
	__le32 hash;
	__sum16 csum;
	u8 hash_type;
	u8 rx_queue;
	u8 rsvd[24];
};

static_assert(sizeof(struct eth_rx_meta) == 32);

// Sent as the first descriptor of every TX frame; layout matches hw/common/pkg/tx_meta_pkg.sv.
struct eth_tx_meta {
	u8 flags;
	u8 rsvd0;
	__le16 csum_start;
	__le16 csum_offset;
	__le16 frame_len;
	u8 rsvd[24];
} __packed;

static_assert(sizeof(struct eth_tx_meta) == 32);

struct xdma_rx_buffer_info {
	// The page_pool page posted to the device.
	struct page* page;
	// The DMA (bus) address the device writes the frame to.
	dma_addr_t dma;
};

struct xdma_tx_buffer_info {
	// Set on the last descriptor of a frame only.
	struct sk_buff* skb;
	// The DMA (bus) address of this descriptor's fragment.
	dma_addr_t dma;
	// Length of the DMA mapped fragment.
	u32 dma_len;
	// Mapped with skb_frag_dma_map rather than dma_map_single.
	bool is_page;
	// Points at the ring's coherent metadata array; nothing to unmap.
	bool is_meta;
};

struct xdma_rx_ring {
	struct napi_struct napi;

	struct device* dev;
	struct net_device* net_dev;
	// Pointer to the virtual address of the hardware descriptor ring.
	struct xdma_desc* hw_desc_ring_virt;
	struct xdma_result* hw_res_ring_virt;

	// The physical (bus) address of the hardware ring (given to XDMA).
	dma_addr_t hw_desc_ring_phys;
	dma_addr_t hw_res_ring_phys;

	// Pointer to our parallel software descriptor ring.
	struct xdma_rx_buffer_info* sw_ring;

	// Recycles DMA mapped RX pages. Exists while the interface is up.
	struct page_pool* page_pool;

	// Total number of descriptors in the ring (e.g., 256).
	u32 count;

	// Size of these buffer length
	u32 buffer_len;

	// Driver's "Clean" Index: Next desc to check for a completed packet.
	u32 driver_ci;
	// Driver's "Producer" Index: Next slot to post a new, empty buffer.
	u32 driver_pi;

	// Handle to the XDMA engine for this ring.
	struct xdma_engine* c2h_engine;
};

struct xdma_tx_ring {
	struct device* dev;
	struct net_device* net_dev;

	// Used to handle interrupts from driver after sending packets
	struct napi_struct napi;

	// HW descriptor ring for H2C
	struct xdma_desc* hw_desc_ring_virt;
	dma_addr_t hw_desc_ring_phys;

	// Where the hw writes the completed descriptor count
	struct xdma_poll_wb* hw_wb_compl_virt;
	dma_addr_t hw_wb_compl_phys;

	// Pointer to our parallel software descriptor ring.
	struct xdma_tx_buffer_info* sw_ring;

	// One metadata slot per descriptor, indexed like the descriptor ring.
	struct eth_tx_meta* meta_virt;
	dma_addr_t meta_phys;

	// Total number of descriptors in the ring (e.g., 256).
	u32 count;

	// producer/consumer indices
	// Index to place transfer packet from CPU
	u32 driver_pi;
	// Index of packet owned by device for transfer
	u32 driver_ci;

	// Keept track of previous descriptor completed count by hardware
	u32 last_hw_completed;

	// Lock needed to protect queue when multiple cpus try to transmit packets
	spinlock_t lock;

	// Handle to the XDMA engine for this ring.
	struct xdma_engine* h2c_engine;
};

struct net_device_priv {
	unsigned long magic;
	struct pci_dev* pdev;
	struct xdma_dev* xdev;
	struct net_device* net_dev;

	struct xdma_rx_ring* rx_ring;
	struct xdma_tx_ring* tx_ring;

	// SFP port, also the XDMA H2C/C2H channel this netdev uses.
	int port;
};

struct eth_pci_dev {
	struct xdma_dev* xdev;
	int num_ports;
	struct net_device* net_devs[ETH_MAX_PORTS];
};

// eth_netdev.c — NAPI poll callbacks (needed by ring files for netif_napi_add)
int rx_napi_poll(struct napi_struct* napi, int weight);
int tx_napi_poll(struct napi_struct* napi, int weight);

// eth_rx_ring.c
int rx_ring_init(struct net_device_priv* xndev);
void rx_ring_free(struct net_device_priv* xndev);
int stop_rx_sgdma(struct xdma_rx_ring* rx_ring);
void free_rx_pages(struct xdma_rx_ring* rx_ring);
void rx_xdma_desc_set(struct xdma_rx_ring* rx_ring, u32 idx, dma_addr_t dma, int len);
int configure_rx(struct net_device_priv* xndev);

// eth_tx_ring.c
int tx_ring_init(struct net_device_priv* xndev);
void tx_ring_free(struct net_device_priv* xndev);
int stop_tx_sgdma(struct xdma_tx_ring* tx_ring);
void tx_xdma_desc_set(struct xdma_desc* hw_desc_ring_virt, dma_addr_t dma, int len, bool eop);
int configure_tx(struct net_device_priv* xndev);

// eth_netdev.c
extern const struct net_device_ops netdev_ops;

#endif
