// SPDX-License-Identifier: GPL-2.0
/*
 * Annapurna Labs Alpine SGPO (serial GPIO output) driver.
 *
 * Port of Ubiquiti's UNVR 4.1.37 drivers/gpio/gpio-alpine-sgpo.c
 * (Copyright (C) 2015 Annapurna Labs Ltd.) to Linux 6.18.  On the UNVR the
 * SGPO lines drive the per-bay SATA activity LEDs.  U-Boot configures the SGPO
 * block (sgpo_init in the board DT); this driver only sets output values.
 */
#include <linux/gpio/driver.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <al_hal_sgpo.h>

struct al_sgpo {
	struct al_sgpo_if	sgpo_if;
	struct gpio_chip	chip;
};

static int al_sgpo_set(struct gpio_chip *chip, unsigned int offset, int value)
{
	struct al_sgpo *gpio = gpiochip_get_data(chip);

	al_sgpo_user_val_set(&gpio->sgpo_if, offset, !!value);
	return 0;
}

static int al_sgpo_dir_out(struct gpio_chip *chip, unsigned int offset, int value)
{
	return al_sgpo_set(chip, offset, value);
}

static int al_sgpo_get_direction(struct gpio_chip *chip, unsigned int offset)
{
	return GPIO_LINE_DIRECTION_OUT;
}

static int al_sgpo_probe(struct platform_device *pdev)
{
	struct al_sgpo *gpio;
	void __iomem *base;
	int err;

	gpio = devm_kzalloc(&pdev->dev, sizeof(*gpio), GFP_KERNEL);
	if (!gpio)
		return -ENOMEM;

	base = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(base))
		return PTR_ERR(base);

	err = al_sgpo_handle_init(&gpio->sgpo_if, base, 1);
	if (err)
		return err;

	gpio->chip.label = "al-sgpo";
	gpio->chip.parent = &pdev->dev;
	gpio->chip.owner = THIS_MODULE;
	gpio->chip.base = -1;
	gpio->chip.can_sleep = false;
	gpio->chip.ngpio = AL_SGPO_PINS_NUM;
	gpio->chip.get_direction = al_sgpo_get_direction;
	gpio->chip.direction_output = al_sgpo_dir_out;
	gpio->chip.set = al_sgpo_set;

	err = devm_gpiochip_add_data(&pdev->dev, &gpio->chip, gpio);
	if (err)
		return err;

	dev_info(&pdev->dev, "Alpine SGPO, %u lines\n", AL_SGPO_PINS_NUM);
	return 0;
}

static const struct of_device_id al_sgpo_ids[] = {
	{ .compatible = "annapurna-labs,alpine-sgpo" },
	{ }
};
MODULE_DEVICE_TABLE(of, al_sgpo_ids);

static struct platform_driver al_sgpo_driver = {
	.probe = al_sgpo_probe,
	.driver = {
		.name		= "al-sgpo",
		.of_match_table	= al_sgpo_ids,
	},
};
module_platform_driver(al_sgpo_driver);

MODULE_DESCRIPTION("Annapurna Labs Alpine SGPO driver");
MODULE_LICENSE("GPL");
