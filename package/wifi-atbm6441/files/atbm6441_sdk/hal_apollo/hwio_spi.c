#include <linux/types.h>

#include "apollo.h"
#include "hwio_spi.h"
#include "bh_spi.h"
#include "sbus.h"

int atbm_read_status(struct atbm_common *priv, u32 *status)
{
	int ret = 0;
	u32 stat= 0;
	
	BUG_ON(!priv->sbus_ops);
	ret = priv->sbus_ops->sbus_read_status(priv->sbus_priv,
					&stat, sizeof(stat));
	if (ret == 0)
	{
		*status = stat;
	}
	return ret;
}

int atbm_read_status_ready(struct atbm_common *priv, u32 *ready)
{
	int ret = 0;
	u32 rdy = 0;
	
	BUG_ON(!priv->sbus_ops);
	ret = priv->sbus_ops->sbus_read_ready(priv->sbus_priv,
					&rdy);
	if (ret == 0)
	{
		*ready = rdy;
	}
	return ret;
}

int atbm_read_status_channelflag(struct atbm_common *priv, u32 *channelflag)
{
	int ret = 0;
	u32 chanflag = 0;
	
	BUG_ON(!priv->sbus_ops);
	ret = priv->sbus_ops->sbus_read_channelflag(priv->sbus_priv,
					&chanflag);
	if (ret == 0)
	{
		*channelflag = chanflag;
	}
	return ret;
}


int atbm_update_status_channelflag(struct atbm_common *priv)
{
	int ret = 0;
	
	BUG_ON(!priv->sbus_ops);
	ret = priv->sbus_ops->sbus_update_channelflag(priv->sbus_priv);
	return ret;
}


static int atbm_read_block(struct atbm_common *priv, void *buf, u32 buf_len)
{
	int ret = 0;
	
	BUG_ON(!priv->sbus_ops);
	ret = priv->sbus_ops->sbus_read_data(priv->sbus_priv,
					buf, buf_len);
	
	return ret;
}

static int atbm_write_block(struct atbm_common *priv,  const void *buf, u32 buf_len)
{
	int ret = 0;	
	BUG_ON(!priv->sbus_ops);
	
	ret = priv->sbus_ops->sbus_write_data(priv->sbus_priv,
					buf, buf_len);
	return ret;
}

int atbm_read_data(struct atbm_common *priv,  void *buf, u32 buf_len)
{	
	int ret = 0;
	u32 status = 0;
//	int retrynum = 0;

	if (buf_len % SPI_READ_BLOCK_SIZE)
	{
		atbm_printk_err("atbm_read_data error buf_len%%SPI_READ_BLOCK_SIZE !=0 \n");
		return -1;
	}
		
//retry:
		ret = atbm_read_block(priv, buf, buf_len);
		if (ret)
		{
			atbm_printk_err("atbm_read_data error\n");
			goto out;
		}

		ret = atbm_read_status(priv, &status);
		if (ret)
		{
			atbm_printk_err( "atbm_read_status error\n");
			goto out;
			
		}else
		{
#if 0
			if (status & SPI_UNDERRUN)
			{
				retrynum++;
				if (retrynum > 5)
				{
					printk( "spi retry times too mach, return failed\n");
					ret = -1;	
					goto out;			
				}
				printk( "spi under error\n");
				printk( "spi retry\n");
				goto retry;
			}
#endif
		}
out:

	return ret;
}

int atbm_write_data(struct atbm_common *priv,  const void *buf, u32 buf_len)
{	
	int ret = 0;
	u32 status = 0;
	int totalLen = 0;
	int retrynum = 0;

	if (buf_len % SPI_WRITE_BLOCK_SIZE)
	{
		atbm_printk_err("atbm_write_data error buf_len%%SPI_WRITE_BLOCK_SIZE !=0 \n");
		return -1;
	}

	for (totalLen = 0; totalLen < buf_len; totalLen += SPI_WRITE_BLOCK_SIZE)
	{
retry:
		ret = atbm_write_block(priv, buf + totalLen, SPI_WRITE_BLOCK_SIZE);
		if (ret)
		{
			atbm_printk_err("atbm_write_data error\n");
			break;
		}

		ret = atbm_read_status(priv, &status);
		if (ret)
		{
			atbm_printk_err("atbm_read_status error\n");
			break;
		}else
		{
			if (status & SPI_OVERRUN)
			{
				retrynum++;
				if (retrynum > 5)
				{
					atbm_printk_err( "spi retry times too mach, return failed\n");
					ret = -1;
					break;
				}
				atbm_printk_err( "spi overrun error\n");
				atbm_printk_err( "spi retry\n");
				goto retry;
			}
		}
	}


	return ret;
}

int atbm_fw_write(struct atbm_common *priv, u32 addr, const void *buf,
                        u32 buf_len)
{
	int ret = 0;
	
	BUG_ON(!priv->sbus_ops);
	
	ret = priv->sbus_ops->sbus_write_firmware(priv->sbus_priv,
							addr, buf, buf_len);

	return ret;
}


int atbm_direct_read_reg_32(struct atbm_common *hw_priv, u32 addr, u32 *val)
{
    int ret = 0;
	*val = 0xffff;
	return ret;
}


int atbm_direct_write_reg_32(struct atbm_common *hw_priv, u32 addr, u32 val)
{
    int ret = 0;

	return ret;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
int atbm_before_load_firmware(struct atbm_common *hw_priv)
{
	u32 status = 0;
	int count = 0;
	while (1)
	{
		atbm_read_status(hw_priv, &status);
		
		if (SPI_HW_SW_RDY & status)
		{
			break;	
		}
		
		count++;
		if (count > 1000)
		{
			atbm_printk_err("wait spi SPI_HW_SW_RDY timeout\n");
			break;
		}
	}
	return 0;
}


int atbm_after_load_firmware(struct atbm_common *hw_priv)
{ 
	int ret;
	int count = 0;
	u32 ready;
	BUG_ON(!hw_priv->sbus_ops);
	ret = hw_priv->sbus_ops->sbus_reset_cpu(hw_priv->sbus_priv);

	do{
		atbm_read_status_ready(hw_priv, &ready);
		if (ready != 0)
		{
			atomic_set(&hw_priv->hw_ready, 1);
			wake_up(&hw_priv->bh_wq);
			ret = 0;
			break;
		}
		msleep(600);
		atbm_printk_init("[probe] wait hw ready %d\n", count);
		count++;
		if (count > 20)
		{
			atbm_printk_err("[probe] wait hw ready timeout\n");
			ret = -1;
			break;
		}
	}while(1);
	
	msleep(2000);
	return ret;
}
void atbm_firmware_init_check(struct atbm_common *hw_priv)
{


}

