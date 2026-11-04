#define pr_fmt(fmt) KBUILD_MODNAME ":%s: " fmt, __func__

#include <linux/if_ether.h>
#include <linux/etherdevice.h>
#include <linux/module.h>
#include <linux/pci.h>

#include "eth_mod.h"
#include "version.h"

#define DRV_MODULE_NAME		"eth_mod"
#define DRV_MODULE_DESC		"XDMA Ethernet Driver Module"

static const char version[] =
	DRV_MODULE_DESC " " DRV_MODULE_NAME " v" DRV_MODULE_VERSION "\n";

MODULE_AUTHOR("Donald Carl");
MODULE_DESCRIPTION(DRV_MODULE_DESC);
MODULE_VERSION(DRV_MODULE_VERSION);
MODULE_LICENSE("GPL");

static int xpdev_cnt;

static const struct pci_device_id pci_ids[] = {
{ PCI_DEVICE(0x10ee, 0x9048), },
{ PCI_DEVICE(0x10ee, 0x9044), },
{ PCI_DEVICE(0x10ee, 0x9042), },
{ PCI_DEVICE(0x10ee, 0x9041), },
{ PCI_DEVICE(0x10ee, 0x903f), },
{ PCI_DEVICE(0x10ee, 0x9038), },
{ PCI_DEVICE(0x10ee, 0x9028), },
{ PCI_DEVICE(0x10ee, 0x9018), },
{ PCI_DEVICE(0x10ee, 0x9034), },
{ PCI_DEVICE(0x10ee, 0x9024), },
{ PCI_DEVICE(0x10ee, 0x9014), },
{ PCI_DEVICE(0x10ee, 0x9032), },
{ PCI_DEVICE(0x10ee, 0x9022), },
{ PCI_DEVICE(0x10ee, 0x9012), },
{ PCI_DEVICE(0x10ee, 0x9031), },
{ PCI_DEVICE(0x10ee, 0x9021), },
{ PCI_DEVICE(0x10ee, 0x9011), },

{ PCI_DEVICE(0x10ee, 0x8011), },
{ PCI_DEVICE(0x10ee, 0x8012), },
{ PCI_DEVICE(0x10ee, 0x8014), },
{ PCI_DEVICE(0x10ee, 0x8018), },
{ PCI_DEVICE(0x10ee, 0x8021), },
{ PCI_DEVICE(0x10ee, 0x8022), },
{ PCI_DEVICE(0x10ee, 0x8024), },
{ PCI_DEVICE(0x10ee, 0x8028), },
{ PCI_DEVICE(0x10ee, 0x8031), },
{ PCI_DEVICE(0x10ee, 0x8032), },
{ PCI_DEVICE(0x10ee, 0x8034), },
{ PCI_DEVICE(0x10ee, 0x8038), },

{ PCI_DEVICE(0x10ee, 0x7011), },
{ PCI_DEVICE(0x10ee, 0x7012), },
{ PCI_DEVICE(0x10ee, 0x7014), },
{ PCI_DEVICE(0x10ee, 0x7018), },
{ PCI_DEVICE(0x10ee, 0x7021), },
{ PCI_DEVICE(0x10ee, 0x7022), },
{ PCI_DEVICE(0x10ee, 0x7024), },
{ PCI_DEVICE(0x10ee, 0x7028), },
{ PCI_DEVICE(0x10ee, 0x7031), },
{ PCI_DEVICE(0x10ee, 0x7032), },
{ PCI_DEVICE(0x10ee, 0x7034), },
{ PCI_DEVICE(0x10ee, 0x7038), },

{ PCI_DEVICE(0x10ee, 0x6828), },
{ PCI_DEVICE(0x10ee, 0x6830), },
{ PCI_DEVICE(0x10ee, 0x6928), },
{ PCI_DEVICE(0x10ee, 0x6930), },
{ PCI_DEVICE(0x10ee, 0x6A28), },
{ PCI_DEVICE(0x10ee, 0x6A30), },
{ PCI_DEVICE(0x10ee, 0x6D30), },

{ PCI_DEVICE(0x10ee, 0x4808), },
{ PCI_DEVICE(0x10ee, 0x4828), },
{ PCI_DEVICE(0x10ee, 0x4908), },
{ PCI_DEVICE(0x10ee, 0x4A28), },
{ PCI_DEVICE(0x10ee, 0x4B28), },

{ PCI_DEVICE(0x10ee, 0x2808), },

{ PCI_DEVICE(0x1d0f, 0x1042), 0 },

/* aws */
{ PCI_DEVICE(0x1d0f, 0xf000), },
{ PCI_DEVICE(0x1d0f, 0xf001), },

{ 0 }
};

MODULE_DEVICE_TABLE(pci, pci_ids);

static void init_net_dev_priv(struct net_device_priv *xndev,
			      struct pci_dev *pdev)
{
	memset(xndev, 0, sizeof(*xndev));

	xndev->magic = MAGIC_DEVICE;
	xndev->pdev = pdev;
	xndev->user_max = MAX_USER_IRQ;
	xndev->h2c_channel_max = XDMA_CHANNEL_NUM_MAX;
	xndev->c2h_channel_max = XDMA_CHANNEL_NUM_MAX;

	xpdev_cnt++;
}

static int probe_one(struct pci_dev *pdev, const struct pci_device_id *id)
{
	struct net_device *net_dev;
	struct net_device_priv *xndev;
	struct xdma_dev *xdev;
	void *hndl = NULL;
	int rv;
	const unsigned char my_mac_addr[ETH_ALEN] = {0x00, 0x0A, 0x35,
						      0x01, 0x02, 0x03};

	pr_info("My driver: Found a matching device!\n");
	net_dev = alloc_etherdev(sizeof(*xndev));
	if (!net_dev)
		return -ENOMEM;

	xndev = netdev_priv(net_dev);
	init_net_dev_priv(xndev, pdev);
	xndev->net_dev = net_dev;

	hndl = xdma_netdev_open(DRV_MODULE_NAME, pdev, &xndev->user_max,
				&xndev->h2c_channel_max, &xndev->c2h_channel_max);
	if (!hndl) {
		rv = -EINVAL;
		goto err_out;
	}

	if (xndev->user_max > MAX_USER_IRQ) {
		pr_err("Maximum users limit reached\n");
		rv = -EINVAL;
		goto err_out;
	}

	if (xndev->h2c_channel_max > XDMA_CHANNEL_NUM_MAX) {
		pr_err("Maximun H2C channel limit reached\n");
		rv = -EINVAL;
		goto err_out;
	}

	if (xndev->c2h_channel_max > XDMA_CHANNEL_NUM_MAX) {
		pr_err("Maximun C2H channel limit reached\n");
		rv = -EINVAL;
		goto err_out;
	}

	if (!xndev->h2c_channel_max && !xndev->c2h_channel_max)
		pr_warn("NO engine found!\n");

	if (xndev->user_max) {
		u32 mask = (1 << (xndev->user_max + 1)) - 1;

		rv = xdma_user_isr_enable(hndl, mask);
		if (rv)
			goto err_out;
	}

	/* make sure no duplicate */
	xdev = xdev_find_by_pdev(pdev);
	if (!xdev) {
		pr_warn("No xdev found!\n");
		rv = -EINVAL;
		goto err_out;
	}

	if (hndl != xdev) {
		pr_err("xdev handle mismatch\n");
		rv = -EINVAL;
		goto err_out;
	}

	pr_info("%s xdma%d, pdev 0x%p, xdev 0x%p, 0x%p, usr %d, ch %d,%d.\n",
		dev_name(&pdev->dev), xdev->idx, pdev, xndev, xdev,
		xndev->user_max, xndev->h2c_channel_max, xndev->c2h_channel_max);

	xndev->xdev = hndl;

	net_dev->hw_features |= NETIF_F_RXFCS;
	net_dev->hw_features |= NETIF_F_RXALL;

	net_dev->netdev_ops = &netdev_ops;
	net_dev->watchdog_timeo = WATCHDOG_PERIOD;

	eth_hw_addr_set(net_dev, my_mac_addr);

	SET_NETDEV_DEV(net_dev, &pdev->dev);
	net_dev->dev.parent = &pdev->dev;

	rv = rx_ring_init(xndev);
	if (rv) {
		pr_err("Failed to init rx_ring: %d\n", rv);
		goto err_out;
	}

	rv = tx_ring_init(xndev);
	if (rv) {
		pr_err("Failed to init tx_ring: %d\n", rv);
		goto err_tx_ring_init;
	}

	rv = register_netdev(net_dev);
	if (rv) {
		pr_err("Failed to register net_dev: %d\n", rv);
		goto err_register_netdev;
	}

	pci_set_drvdata(pdev, net_dev);

	pr_info("Registered network device %s\n", net_dev->name);

	return 0;

err_register_netdev:
	tx_ring_free(xndev);
err_tx_ring_init:
	rx_ring_free(xndev);
err_out:
	pr_info("xdev 0x%p xdma_device_close.\n", hndl);
	xdma_device_close(pdev, hndl);
	xpdev_cnt--;

	pr_err("pdev 0x%p, err %d.\n", pdev, rv);
	free_netdev(net_dev);
	return rv;
}

static void remove_one(struct pci_dev *pdev)
{
	struct net_device *net_dev = pci_get_drvdata(pdev);
	struct net_device_priv *xndev;
	struct xdma_dev *xdev;

	if (!net_dev)
		return;

	xndev = netdev_priv(net_dev);
	xdev = xndev->xdev;

	unregister_netdev(net_dev);

	tx_ring_free(xndev);
	rx_ring_free(xndev);

	xdma_device_close(pdev, xdev);
	xpdev_cnt--;

	pci_set_drvdata(pdev, NULL);
	free_netdev(net_dev);
}

static struct pci_driver pci_driver = {
	.name     = DRV_MODULE_NAME,
	.id_table = pci_ids,
	.probe    = probe_one,
	.remove   = remove_one,
};

static int eth_xdma_mod_init(void)
{
	pr_info("%s", version);
	return pci_register_driver(&pci_driver);
}

static void eth_xdma_mod_exit(void)
{
	dbg_init("pci_unregister_driver.\n");
	pci_unregister_driver(&pci_driver);
}

module_init(eth_xdma_mod_init);
module_exit(eth_xdma_mod_exit);
