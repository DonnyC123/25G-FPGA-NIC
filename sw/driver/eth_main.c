#define pr_fmt(fmt) KBUILD_MODNAME ":%s: " fmt, __func__

#include <linux/if_ether.h>
#include <linux/etherdevice.h>
#include <linux/module.h>
#include <linux/pci.h>

#include "eth_mod.h"
#include "version.h"

#define DRV_MODULE_NAME "eth_mod"
#define DRV_MODULE_DESC "XDMA Ethernet Driver Module"

static const char version[] = DRV_MODULE_DESC " " DRV_MODULE_NAME " v" DRV_MODULE_VERSION "\n";

MODULE_AUTHOR("Donald Carl");
MODULE_DESCRIPTION(DRV_MODULE_DESC);
MODULE_VERSION(DRV_MODULE_VERSION);
MODULE_LICENSE("GPL");

static int xpdev_cnt;

// clang-format off
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

// aws
{ PCI_DEVICE(0x1d0f, 0xf000), },
{ PCI_DEVICE(0x1d0f, 0xf001), },

{ 0 }
};
// clang-format on

MODULE_DEVICE_TABLE(pci, pci_ids);

static int eth_port_probe(struct eth_pci_dev* epdev, struct pci_dev* pdev, int port) {
	const unsigned char mac_addr[ETH_ALEN] = {0x00, 0x0A, 0x35, 0x01, 0x02, 0x03 + port};

	struct net_device* net_dev = alloc_etherdev(sizeof(struct net_device_priv));
	if (!net_dev)
		return -ENOMEM;

	struct net_device_priv* xndev = netdev_priv(net_dev);
	xndev->magic = MAGIC_DEVICE;
	xndev->pdev = pdev;
	xndev->xdev = epdev->xdev;
	xndev->net_dev = net_dev;
	xndev->port = port;

	net_dev->netdev_ops = &netdev_ops;
	net_dev->watchdog_timeo = WATCHDOG_PERIOD;
	// tx features
	net_dev->hw_features |= TX_FEATURES;
	net_dev->features |= TX_FEATURES;
	net_dev->vlan_features |= TX_FEATURES;
	// rx features
	net_dev->hw_features |= NETIF_F_RXCSUM | NETIF_F_RXHASH;
	net_dev->features |= NETIF_F_RXCSUM | NETIF_F_RXHASH;

	eth_hw_addr_set(net_dev, mac_addr);

	SET_NETDEV_DEV(net_dev, &pdev->dev);
	net_dev->dev.parent = &pdev->dev;

	int rv = rx_ring_init(xndev);
	if (rv) {
		pr_err("Failed to init rx_ring: %d\n", rv);
		goto err_rx_ring_init;
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

	epdev->net_devs[port] = net_dev;

	pr_info("Registered network device %s on port %d\n", net_dev->name, port);

	return 0;

err_register_netdev:
	tx_ring_free(xndev);
err_tx_ring_init:
	rx_ring_free(xndev);
err_rx_ring_init:
	free_netdev(net_dev);
	return rv;
}

static void eth_port_remove(struct net_device* net_dev) {
	struct net_device_priv* xndev = netdev_priv(net_dev);

	unregister_netdev(net_dev);

	tx_ring_free(xndev);
	rx_ring_free(xndev);

	free_netdev(net_dev);
}

static void eth_remove_ports(struct eth_pci_dev* epdev) {
	for (int port = epdev->num_ports - 1; port >= 0; port--) {
		struct net_device* net_dev = epdev->net_devs[port];
		if (!net_dev)
			continue;

		eth_port_remove(net_dev);
		epdev->net_devs[port] = NULL;
	}
}

static int probe_one(struct pci_dev* pdev, const struct pci_device_id* id) {
	int h2c_channel_max = XDMA_CHANNEL_NUM_MAX;
	int c2h_channel_max = XDMA_CHANNEL_NUM_MAX;
	int user_max = MAX_USER_IRQ;
	int rv;

	pr_info("My driver: Found a matching device!\n");
	struct eth_pci_dev* epdev = kzalloc(sizeof(*epdev), GFP_KERNEL);
	if (!epdev)
		return -ENOMEM;

	void* hndl = xdma_netdev_open(DRV_MODULE_NAME, pdev, &user_max, &h2c_channel_max, &c2h_channel_max);
	if (!hndl) {
		rv = -EINVAL;
		goto err_free;
	}

	xpdev_cnt++;

	if (user_max > MAX_USER_IRQ) {
		pr_err("Maximum users limit reached\n");
		rv = -EINVAL;
		goto err_close;
	}

	if (h2c_channel_max > XDMA_CHANNEL_NUM_MAX) {
		pr_err("Maximun H2C channel limit reached\n");
		rv = -EINVAL;
		goto err_close;
	}

	if (c2h_channel_max > XDMA_CHANNEL_NUM_MAX) {
		pr_err("Maximun C2H channel limit reached\n");
		rv = -EINVAL;
		goto err_close;
	}

	if (user_max) {
		u32 mask = (1 << (user_max + 1)) - 1;

		rv = xdma_user_isr_enable(hndl, mask);
		if (rv)
			goto err_close;
	}

	// make sure no duplicate
	struct xdma_dev* xdev = xdev_find_by_pdev(pdev);
	if (!xdev) {
		pr_warn("No xdev found!\n");
		rv = -EINVAL;
		goto err_close;
	}

	if (hndl != xdev) {
		pr_err("xdev handle mismatch\n");
		rv = -EINVAL;
		goto err_close;
	}

	epdev->xdev = xdev;
	epdev->num_ports = min3(h2c_channel_max, c2h_channel_max, ETH_MAX_PORTS);
	if (!epdev->num_ports) {
		pr_err("No H2C/C2H channel pair found\n");
		rv = -ENODEV;
		goto err_close;
	}

	pr_info("%s xdma%d, pdev 0x%p, xdev 0x%p, usr %d, ch %d,%d, ports %d.\n", dev_name(&pdev->dev), xdev->idx,
		pdev, xdev, user_max, h2c_channel_max, c2h_channel_max, epdev->num_ports);

	for (int port = 0; port < epdev->num_ports; port++) {
		rv = eth_port_probe(epdev, pdev, port);
		if (rv) {
			pr_err("Failed to probe port %d: %d\n", port, rv);
			goto err_ports;
		}
	}

	pci_set_drvdata(pdev, epdev);

	return 0;

err_ports:
	eth_remove_ports(epdev);
err_close:
	pr_info("xdev 0x%p xdma_device_close.\n", hndl);
	xdma_device_close(pdev, hndl);
	xpdev_cnt--;
err_free:
	pr_err("pdev 0x%p, err %d.\n", pdev, rv);
	kfree(epdev);
	return rv;
}

static void remove_one(struct pci_dev* pdev) {
	struct eth_pci_dev* epdev = pci_get_drvdata(pdev);
	if (!epdev)
		return;

	eth_remove_ports(epdev);

	xdma_device_close(pdev, epdev->xdev);
	xpdev_cnt--;

	pci_set_drvdata(pdev, NULL);
	kfree(epdev);
}

static struct pci_driver pci_driver = {
	.name = DRV_MODULE_NAME,
	.id_table = pci_ids,
	.probe = probe_one,
	.remove = remove_one,
};

static int eth_xdma_mod_init(void) {
	pr_info("%s", version);
	return pci_register_driver(&pci_driver);
}

static void eth_xdma_mod_exit(void) {
	dbg_init("pci_unregister_driver.\n");
	pci_unregister_driver(&pci_driver);
}

module_init(eth_xdma_mod_init);
module_exit(eth_xdma_mod_exit);
