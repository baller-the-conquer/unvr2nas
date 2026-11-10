/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Glue for building Ubiquiti's UNVR (Annapurna Labs Alpine V2) al_eth driver
 * out of tree against a modern mainline kernel.  Force-included into every
 * object via Kbuild (-include).
 */
#ifndef _AL_ETH_PORT_H
#define _AL_ETH_PORT_H

#include <linux/version.h>
#include <linux/kconfig.h>

/* PCI IDs from Ubiquiti's include/linux/pci_ids.h */
#ifndef PCI_VENDOR_ID_ANNAPURNA_LABS
#define PCI_VENDOR_ID_ANNAPURNA_LABS	0x1c36
#endif
#define PCI_DEVICE_ID_AL_ETH		0x0001
#define PCI_DEVICE_ID_AL_ETH_ADVANCED	0x0002
#define PCI_DEVICE_ID_AL_ETH_NIC	0x0004

/* Rx buffer mode: the vendor Kconfig default */
#if !defined(CONFIG_AL_ETH_ALLOC_SKB) && !defined(CONFIG_AL_ETH_ALLOC_PAGE)
#define CONFIG_AL_ETH_ALLOC_FRAG 1
#endif

/* HAL module init hooks (were arch/subsys/fs initcalls in the vendor tree) */
int al_eth_hal_init(void);
void al_eth_hal_exit(void);



#include <linux/pci.h>
#include <linux/dma-mapping.h>

/* pci_dma_* wrappers were removed in 5.18 */
#define pci_dma_sync_single_for_cpu(pdev, a, s, d) \
	dma_sync_single_for_cpu(&(pdev)->dev, (a), (s), (enum dma_data_direction)(d))
#define pci_dma_sync_single_for_device(pdev, a, s, d) \
	dma_sync_single_for_device(&(pdev)->dev, (a), (s), (enum dma_data_direction)(d))

/*
 * pci_enable_msix() was removed in 4.x.  Keep its contract: 0 on success,
 * >0 = "try again with fewer vectors", <0 = error.
 */
static inline int al_eth_pci_enable_msix(struct pci_dev *pdev, struct msix_entry *e, int nvec)
{
	int rc = pci_enable_msix_range(pdev, e, nvec, nvec);

	if (rc == -ENOSPC && nvec > 1)
		return 1;
	return rc < 0 ? rc : 0;
}
#endif /* _AL_ETH_PORT_H */
