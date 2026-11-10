// SPDX-License-Identifier: GPL-2.0
/*
 * In Ubiquiti's kernel the Alpine serdes / group-LM HAL is built in and set up
 * by arch/subsys/fs initcalls.  Here it lives inside al_eth.ko, so run that
 * setup from module init, before the PCI driver registers.
 */
#include <linux/init.h>
#include <linux/printk.h>
#include <linux/module.h>

/* The UNVR's RGMII port has an external PHY on MDIO; its driver must be bound
 * before al_eth registers the bus, or probe fails with "phy device get failed". */
MODULE_SOFTDEP("pre: marvell realtek");

int al_serdes_resource_init(void);
int alpine_serdes_grp_objs_init(void);
int alpine_group_lm_init(void);

int al_eth_hal_init(void)
{
	int rc;

	rc = al_serdes_resource_init();
	if (rc)
		return rc;
	rc = alpine_serdes_grp_objs_init();
	if (rc)
		return rc;
	return alpine_group_lm_init();
}

void al_eth_hal_exit(void)
{
}
