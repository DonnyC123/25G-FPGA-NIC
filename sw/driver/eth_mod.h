
#ifndef __ETH_MODULE_H__
#define __ETH_MODULE_H__

#include <linux/aio.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/fb.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/jiffies.h>
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/mm_types.h>
#include <linux/module.h>
#include <linux/netdevice.h>
#include <linux/pci.h>
#include <linux/poll.h>
#include <linux/sched.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/spinlock_types.h>
#include <linux/splice.h>
#include <linux/types.h>
#include <linux/uio.h>
#include <linux/version.h>
#include <linux/vmalloc.h>
#include <linux/workqueue.h>

#include "libxdma.h"
#include "xdma_thread.h"

#define SGDMA_COMMON_OFFSET	(6 * TARGET_SPACING)

#ifdef __LIBXDMA_DEBUG__
#define write_register(v, mem, off) __write_register(__func__, v, mem, off)
#else
#define write_register(v, mem, off) iowrite32(v, mem)
#endif

#define XDMA_CTRL_RUN_AND_IE \
    (XDMA_CTRL_RUN_STOP               | \
     XDMA_CTRL_IE_DESC_STOPPED        | \
     XDMA_CTRL_IE_DESC_COMPLETED      | \
     XDMA_CTRL_IE_DESC_ALIGN_MISMATCH | \
     XDMA_CTRL_IE_MAGIC_STOPPED       | \
     XDMA_CTRL_IE_IDLE_STOPPED        | \
     XDMA_CTRL_IE_READ_ERROR          | \
     XDMA_CTRL_IE_DESC_ERROR)

#define MAGIC_ENGINE 0xEEEEEEEEUL
#define MAGIC_DEVICE 0xDDDDDDDDUL
#define MAGIC_CHAR 0xCCCCCCCCUL
#define MAGIC_BITSTREAM 0xBBBBBBBBUL

#define WATCHDOG_PERIOD (5 * HZ)
#define RX_BUFFER_LEN 2048
#define SGDMA_TIMEOUT 50
#define MAX_NAPI_PACKETS_PER_CALL 64
#define XDMA_C2H_CREDIT_MAX 1023


struct xdma_rx_buffer_info {
  /** The sk_buff holding the empty buffer we posted. */
  struct sk_buff *skb;
  /** The DMA (bus) address of the sk_buff's data. */
  dma_addr_t sk_buff_phys;
};

struct xdma_tx_buffer_info {
  /** The sk_buff holding the empty buffer we posted. */
  struct sk_buff *skb;
  /** The DMA (bus) address of the sk_buff's data. */
  dma_addr_t sk_buff_phys;
  // Store length of dma mapped buffer
  u32 dma_len;
};

struct xdma_rx_ring {
  struct napi_struct napi;

  struct device *dev;
  struct net_device *net_dev;
  /** Pointer to the virtual address of the hardware descriptor ring. */
  struct xdma_desc *hw_desc_ring_virt;
  struct xdma_result *hw_res_ring_virt;

  /** The physical (bus) address of the hardware ring (given to XDMA). */
  dma_addr_t hw_desc_ring_phys;
  dma_addr_t hw_res_ring_phys;

  /** Pointer to our parallel software descriptor ring. */
  struct xdma_rx_buffer_info *sw_ring;

  /** Total number of descriptors in the ring (e.g., 256). */
  u32 count;

  /** Size of these buffer length **/
  u32 buffer_len;

  /** Driver's "Clean" Index: Next desc to check for a completed packet. */
  u32 driver_ci;
  /** Driver's "Producer" Index: Next slot to post a new, empty buffer. */
  u32 driver_pi;

  /** Handle to the XDMA engine for this ring. */
  struct xdma_engine *c2h_engine;
};

struct xdma_tx_ring {
  struct device *dev;
  struct net_device *net_dev;

  // Used to handle interrupts from driver after sending packets
  struct napi_struct napi;

  /* HW descriptor ring for H2C */
  struct xdma_desc *hw_desc_ring_virt;
  dma_addr_t hw_desc_ring_phys;

  /** Pointer to our parallel software descriptor ring. */
  struct xdma_tx_buffer_info *sw_ring;

  /** Total number of descriptors in the ring (e.g., 256). */
  u32 count;

  /* producer/consumer indices */
  // Index to place transfer packet from CPU
  u32 driver_pi;
  // Index of packet owned by device for transfer
  u32 driver_ci;

  /* Keept track of previous descriptor completed count by hardware */
  u32 last_hw_completed;

  /*Lock needed to protect queue when multiple cpus try to transmit packets*/
  spinlock_t lock;

  /** Handle to the XDMA engine for this ring. */
  struct xdma_engine *h2c_engine;
};

struct net_device_priv {
  unsigned long magic;
  struct pci_dev *pdev;
  struct xdma_dev *xdev;
  struct net_device *net_dev;

  struct xdma_rx_ring *rx_ring;
  struct xdma_tx_ring *tx_ring;

  int user_max;
  int h2c_channel_max;
  int c2h_channel_max;
};

/* eth_netdev.c — NAPI poll callbacks (needed by ring files for netif_napi_add) */
int rx_napi_poll(struct napi_struct *napi, int weight);
int tx_napi_poll(struct napi_struct *napi, int weight);

/* eth_rx_ring.c */
int rx_ring_init(struct net_device_priv *xndev);
void rx_ring_free(struct net_device_priv *xndev);
int wr_sgdma_desc_regs_rx(struct xdma_rx_ring *rx_ring);
int start_rx_sgdma(struct xdma_rx_ring *rx_ring);
int stop_rx_sgdma(struct xdma_rx_ring *rx_ring);
int alloc_rx_sk_buff(struct xdma_rx_ring *rx_ring);
void free_rx_sk_buff(struct xdma_rx_ring *rx_ring);
void rx_xdma_desc_set(struct xdma_rx_ring *rx_ring, u32 idx,
                      dma_addr_t sk_buff_phys, int len);
int configure_rx(struct net_device_priv *xndev);

/* eth_tx_ring.c */
int tx_ring_init(struct net_device_priv *xndev);
void tx_ring_free(struct net_device_priv *xndev);
int wr_sgdma_desc_regs_tx(struct xdma_tx_ring *tx_ring);
int start_tx_sgdma(struct xdma_tx_ring *tx_ring);
int stop_tx_sgdma(struct xdma_tx_ring *tx_ring);
void tx_xdma_desc_set(struct xdma_desc *hw_desc_ring_virt,
                      dma_addr_t skb_phys, int len);
int configure_tx(struct net_device_priv *xndev);

/* eth_netdev.c */
extern const struct net_device_ops netdev_ops;

#endif
