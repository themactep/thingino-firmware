//extern "C" int delay_sdio(int );
#define delay_sdio(a) (mdelay((a)/1000))
#include "dcxo_dpll.h"
int dcxo_fail=0;
bool debugMode;

#define READ_DPLL_VALUE
#define READ_DCXO_VALUE
#define SMU_BASE_ADDR 0x16100000 
#define SMU_DCXO_TRIM_ADDR SMU_BASE_ADDR+0x100c
#define SMU_DCXO_CRTRL_ADDR SMU_BASE_ADDR+0x1010
#define SMU_DPLL_PARAM_1_ADDR SMU_BASE_ADDR+0x1018
#define SMU_DPLL_PARAM_2_ADDR SMU_BASE_ADDR+0x101c
#define SMU_DPLL_FRAC_ADDR SMU_BASE_ADDR+0x1020
#define SMU_DPLL_CTRL_ADDR SMU_BASE_ADDR+0x1024
static u8 dpll_regdata_tbl[96/8];
static u8 dcxo_regdata_tbl[96/8];
u8 find_dcxo_dpll_reg(const char *source,char *dest){
u8 reg_value;
char *option;
if((option=strstr(source,dest))!=NULL){
	reg_value=simple_strtoul(option+strlen(dest),NULL,0);
	return reg_value;
}else{
	return 0xff;
}
}
bool enable_debugMode(const char *source,char *dest){
    bool dbgMode;
    char *option;
    if((option=strstr(source,dest))!=NULL){
            dbgMode=simple_strtoul(option+strlen(dest),NULL,0);
            return dbgMode;
    }else{
            return 0;
    }
}

struct dcxo_reg_info {
	u8 data;
	u8 start_bit;
	u8 end_bit;
	u8 valid;
	char *name;
};
#define DCXO_REG_MAX 28
struct dcxo_reg {
	struct dcxo_reg_info info[DCXO_REG_MAX];
};
struct dcxo_reg dcxo_default;
#define DCXO_INIT_DEFAULT(reg_name,startbit,endbit,val) {\
	dcxo_default.info[i].start_bit = startbit;\
	dcxo_default.info[i].end_bit = endbit;\
	dcxo_default.info[i].data = val;\
	dcxo_default.info[i].name = #reg_name;\
	i++;\
}
#define DCXO_REG_READ_DBG_NAME(dcxo_reg_val,start_bit,end_bit,name) do { \
			ret=atbm_reg_write_8(hw_priv,0x18,0xb0+ start_bit/8); \
			ret=atbm_reg_write_8(hw_priv,0x18,0x00+ start_bit/8);\
			ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_reg_val);\
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"****read*real signal***reg%2d**=%x\n",start_bit/8,dcxo_reg_val);\
			ret=atbm_reg_write_8(hw_priv,0x18,0x10+ start_bit/8);\
			ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_reg_val);\
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"***read*sdio value****dcxo_regbit%02d_%02d=%x\n",start_bit,end_bit,dcxo_reg_val);\
			u8 regmask =0; \
			u8 startbit = start_bit%8; \
			u8 endbit = end_bit%8; \
			regmask = ~(BIT(startbit)-1);\
			regmask &=(BIT(endbit)-1)|BIT(endbit); \
			dcxo_reg_val&=regmask; \
			dcxo_reg_val =(dcxo_reg_val>>startbit); \
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"****check***%s BIT[%d~%d]=%x\n",name,start_bit,end_bit,dcxo_reg_val);\
			}while(0)

#define DCXO_REG_READ(start_bit,value) do { \
	ret=atbm_reg_write_8(hw_priv,0x18,0x10 + start_bit/8); \
	if (ret<0){\
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_%d_bit is error!!!",start_bit); \
	}\
	ret=atbm_reg_read_8(hw_priv,0x19,&value);\
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"**read reg%d bit[%d] value 0x%x\n", start_bit/8,start_bit,value);\
}while(0)
int atbm_dcxo_read_default_value(struct atbm_common *hw_priv,const char * test)
{
	int i;
	int ret;
	for(i=0;i<96/8;i++){
		DCXO_REG_READ(i*8,dcxo_regdata_tbl[i]);
	}
	return 0;
}
#define DCXO_CHECK_DEFAULT_NAME(dcxo_data_val,dcxo_reg_val,start_bit,end_bit,name) do { \
				u8 find_buf[32];\
				memset(find_buf,0,32);\
				sprintf(find_buf,"%s:",name); \
				dcxo_data_val=find_dcxo_dpll_reg(dcxo_value,find_buf); \
				if(dcxo_data_val!=0xff) {\
					atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"**insmod**%s=%x,BIT(%d:%d)\n",name,dcxo_data_val,end_bit,start_bit);\
				}\
				if((dcxo_data_val==0xff)&&(dcxo_default_valid)){ \
				if((pinfo->data!=0xff)&&(dcxo_default_valid)){ \
					dcxo_data_val = pinfo->data; \
				} \
			} \
		}while(0)
	
#define DCXO_CHANGE_DEFAULT_NAME(dcxo_data_val,dcxo_reg_val,start_bit,end_bit,name) do { \
			if(dcxo_data_val!=0xff){ \
				u8 regmask =0; \
				u8 startbit = start_bit%8; \
				u8 endbit = end_bit%8; \
				regmask = ~(BIT(startbit)-1);\
				regmask &=(BIT(endbit)-1)|BIT(endbit); \
				atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"**set**%s=%x,BIT(%d:%d), reg= 0x%x ",name,dcxo_data_val,end_bit,start_bit,dcxo_reg_val);\
				dcxo_reg_val&=~regmask; \
				dcxo_reg_val|=(dcxo_data_val<<startbit)&regmask; \
				atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"**change reg 0x%x\n",dcxo_reg_val);\
			}\
		}while(0)
	
	
#define DCXO_REG_WRITE(start_bit,value) do { \
					atbm_reg_write_8(hw_priv,0x18,0x80 + start_bit/8);		 \
					ret=atbm_reg_write_8(hw_priv,0x19,value); \
					atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"**write reg%2d bit[%d] value 0x%x\n", start_bit/8,start_bit,value);\
				}while(0)
			

int  atbm_dcxo_init_default_apolloc(int dpllClock)
{
	int i=0;
	DCXO_INIT_DEFAULT(dcxo_atb_dis,4,4,0x1);
	if(dpllClock==DPLL_CLOCK_24M){
		DCXO_INIT_DEFAULT(dcxo_atb_select,5,5,0x0);
		DCXO_INIT_DEFAULT(dcxo_core_sw_l,6,7,0x0);
		DCXO_INIT_DEFAULT(dcxo_core_sw_h,8,10,0x0);
		DCXO_INIT_DEFAULT(dcxo_ictrl_l,14,15,0x3);
		DCXO_INIT_DEFAULT(dcxo_ictrl_h,16,18,0x8);
	}else{
		DCXO_INIT_DEFAULT(dcxo_atb_select,5,5,0x1);
		DCXO_INIT_DEFAULT(dcxo_core_sw_l,6,7,0x1);
		DCXO_INIT_DEFAULT(dcxo_core_sw_h,8,10,0x4);
		DCXO_INIT_DEFAULT(dcxo_ictrl_l,14,15,0x2);
		DCXO_INIT_DEFAULT(dcxo_ictrl_h,16,18,0x3);
	}
	DCXO_INIT_DEFAULT(dcxo_dpll_clk_en,13,13,0x1);
	DCXO_INIT_DEFAULT(dcxo_ictrl_l,14,15,0x2);
	DCXO_INIT_DEFAULT(dcxo_ictrl_h,16,18,0x3);
	DCXO_INIT_DEFAULT(dcxo_iqcal_en,19,19,0x0);
	DCXO_INIT_DEFAULT(dcxo_ldo_atb_dis,20,20,0x1);
	DCXO_INIT_DEFAULT(dcxo_ldo_byp,21,21,0x0);
	DCXO_INIT_DEFAULT(dcxo_ldo_debug_en,22,22,0x0);
	DCXO_INIT_DEFAULT(dcxo_ldo_load_en,23,23,0x0);
	DCXO_INIT_DEFAULT(dcxo_rfpll_clk_test,27,27,0x0);
	DCXO_INIT_DEFAULT(dcxo_start,28,28,0x1);
	DCXO_INIT_DEFAULT(dcxo_test_en,29,29,0x0);
	if(dpllClock==DPLL_CLOCK_26M){
		DCXO_INIT_DEFAULT(dcxo_trim_l,30,31,0x0);
		DCXO_INIT_DEFAULT(dcxo_trim_h,32,35,0x8);
	}
	else{
		DCXO_INIT_DEFAULT(dcxo_trim_l,30,31,0x0);
		DCXO_INIT_DEFAULT(dcxo_trim_h,32,35,0x4);
	}
	DCXO_INIT_DEFAULT(dcxo_res_cal_l,36,39,0xf);
	DCXO_INIT_DEFAULT(dcxo_res_cal_h,40,46,0x7f);
	DCXO_INIT_DEFAULT(sdio_dcxo_iso_en,47,47,0x0);
	return 0;
}
int atbm_dcxo_test_value_apolloc(struct atbm_common *hw_priv,const char *dcxo_value,int dpllClock)
{
	int ret;
	u8 dcxo_regdata;
	u8 dcxo_tmp;
	u8 dcxo_default_valid= 1;
	int i = 0;
	struct dcxo_reg_info *pinfo;
	//u8 dcxo_regdata_tbl[96/8];
	atbm_dcxo_init_default_apolloc(dpllClock);
	if(strstr(dcxo_value,"dcxo"))
		dcxo_default_valid = 0;
	for(i=0;i<96/8;i++){
		DCXO_REG_READ(i*8,dcxo_regdata_tbl[i]);
	}
	debugMode=enable_debugMode(dcxo_value,"debugMode:");
	for(i=0;i<20/*sizeof(struct dcxo_reg)/sizeof(struct dcxo_reg_info)*/;i++){
		pinfo = &dcxo_default.info[i];
		dcxo_regdata = dcxo_regdata_tbl[pinfo->start_bit/8];
		DCXO_CHECK_DEFAULT_NAME(dcxo_tmp,dcxo_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
		DCXO_CHANGE_DEFAULT_NAME(dcxo_tmp,dcxo_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
		dcxo_regdata_tbl[pinfo->start_bit/8] = dcxo_regdata;
		if((pinfo->start_bit == 6)&&(dcxo_tmp != 0xff)){
			pinfo = &dcxo_default.info[i+1];
			dcxo_regdata = dcxo_regdata_tbl[pinfo->start_bit/8];
			dcxo_tmp = dcxo_tmp >> 6;
			DCXO_CHANGE_DEFAULT_NAME(dcxo_tmp,dcxo_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
			dcxo_regdata_tbl[pinfo->start_bit/8] = dcxo_regdata;
		}
		if((pinfo->start_bit == 14)&&(dcxo_tmp != 0xff)){
			pinfo = &dcxo_default.info[i+1];
			dcxo_regdata = dcxo_regdata_tbl[pinfo->start_bit/8];
			dcxo_tmp = dcxo_tmp >> 7;
			DCXO_CHANGE_DEFAULT_NAME(dcxo_tmp,dcxo_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
			dcxo_regdata_tbl[pinfo->start_bit/8] = dcxo_regdata;
		}
		if((pinfo->start_bit == 30)&&(dcxo_tmp != 0xff)){
			pinfo = &dcxo_default.info[i+1];
			dcxo_regdata = dcxo_regdata_tbl[pinfo->start_bit/8];
			dcxo_tmp = dcxo_tmp >> 7;
			DCXO_CHANGE_DEFAULT_NAME(dcxo_tmp,dcxo_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
			dcxo_regdata_tbl[pinfo->start_bit/8] = dcxo_regdata;
		}
		if((pinfo->start_bit == 36)&&(dcxo_tmp != 0xff)){
			pinfo = &dcxo_default.info[i+1];
			dcxo_regdata = dcxo_regdata_tbl[pinfo->start_bit/8];
			dcxo_tmp = dcxo_tmp >> 4;
			DCXO_CHANGE_DEFAULT_NAME(dcxo_tmp,dcxo_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
			dcxo_regdata_tbl[pinfo->start_bit/8] = dcxo_regdata;
		}

	}

	for(i=0;i<96/8;i++){
		DCXO_REG_WRITE(i*8,dcxo_regdata_tbl[i]);
	}
	//dcxo config finish
	ret=atbm_reg_write_8(hw_priv,0x18,0xbb);

	//atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"***DCXO config finish \n");

	mdelay(100);
	return 0;


}

int  atbm_dcxo_init_default(int dpllClock)
{
	int i=0;
	DCXO_INIT_DEFAULT(dcxo_fine_trim,5,7,0x0);
	DCXO_INIT_DEFAULT(dcxo_res_cal_l,8,15,0xff);
	DCXO_INIT_DEFAULT(dcxo_res_cal_h,16,18,0x07);
	DCXO_INIT_DEFAULT(dcxo_dpll_clk_en,20,20,0x1);
	if(dpllClock==DPLL_CLOCK_26M){
		DCXO_INIT_DEFAULT(dcxo_trim,23,29,0x10);
	}
	else{
		DCXO_INIT_DEFAULT(dcxo_trim,23,29,0x30);
	}
	DCXO_INIT_DEFAULT(dcxo_rfpll_clk_test,30,30,0x0);
	DCXO_INIT_DEFAULT(dcxo_test_en,31,31,0x0);
	DCXO_INIT_DEFAULT(dcxo_iq_sw,32,34,0x0);
	DCXO_INIT_DEFAULT(dcxo_ictrl,35,40,0x38);
	DCXO_INIT_DEFAULT(dcxo_mode_sel,41,42,0x0);
	DCXO_INIT_DEFAULT(dcxo_iqcal_en,43,43,0x0);
	DCXO_INIT_DEFAULT(dcxo_ldo_byp,44,44,0x0);
	DCXO_INIT_DEFAULT(sdio_dcxo_iso_en,45,45,0x0);
	return 0;
}
int atbm_dcxo_test_value(struct atbm_common *hw_priv,const char *dcxo_value,int dpllClock)
{
	int ret;
	u8 dcxo_fine_trim;
	//dcxo_fine_trim
	u8 dcxo_fine_trim_internal;
	int dcxo_default_valid =1;
	u8 dcxo_res_cal_internal_l;
	u8 dcxo_res_cal_l;
	u8 dcxo_res_cal_internal_h;
	u8 dcxo_res_cal_h;
	u8 dcxo_dpll_clk_en_internal;
	u8 dcxo_dpll_clk_en;
	u8 dcxo_trim_internal;
	u8 dcxo_trim;
	u8 dcxo_trim_internal_2;
	u8 dcxo_trim_2;
	u8 dcxo_rfpll_clk_test_internal;
	u8 dcxo_rfpll_clk_test;
	u8 dcxo_test_en_internal;
	u8 dcxo_test_en;
	u8 dcxo_iq_sw_internal;
	u8 dcxo_iq_sw;
	u8 dcxo_ictrl_internal;
	u8 dcxo_ictrl;
	u8 dcxo_ictrl_internal_2;
	u8 dcxo_ictrl_2;
	u8 dcxo_model_sel_internal;
	u8 dcxo_mode_sel;
	u8 dcxo_iqcal_en_internal;
	u8 dcxo_iqcal_en;
	u8 dcxo_ldo_byp_internal;
    u8 dcxo_ldo_byp;
	u8 sdio_dcxo_iso_en_internal;
	u8 sdio_dcxo_iso_en;
	struct dcxo_reg_info *pinfo;

	ret=atbm_dcxo_init_default(dpllClock);

	if(strstr(dcxo_value,"dcxo"))
		dcxo_default_valid = 0;

	ret=atbm_reg_write_8(hw_priv,0x18,0x10);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_fine_trim is error!!!");
	}
	dcxo_fine_trim=find_dcxo_dpll_reg(dcxo_value,"dcxo_fine_trim:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_fine_trim=%x\n",dcxo_fine_trim);
	if (dcxo_fine_trim!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_fine_trim_internal);

		dcxo_fine_trim_internal&=0x1f;
		dcxo_fine_trim_internal|=dcxo_fine_trim<<5;

		ret=atbm_reg_write_8(hw_priv,0x18,0x80);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_fine_trim is error!!!");
		}
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_fine_trim_internal);
	}else if (dcxo_fine_trim==0xff&&dcxo_default_valid){
		pinfo=&dcxo_default.info[0];
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_fine_trim_internal);

		dcxo_fine_trim_internal&=0x1f;
		dcxo_fine_trim_internal|=pinfo->data<<5;

		ret=atbm_reg_write_8(hw_priv,0x18,0x80);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_fine_trim is error!!!");
		}
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_fine_trim_internal);
	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb0);

	debugMode=enable_debugMode(dcxo_value,"debugMode:");
	/******************************************************************/
	if (debugMode){
		ret=atbm_reg_write_8(hw_priv,0x18,0x10);
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_fine_trim_internal);
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_fine_trim_internal=%x\n",dcxo_fine_trim_internal);
	}
	/******************************************************************/
	//dcxo_res_cal
	ret=atbm_reg_write_8(hw_priv,0x18,0x11);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_res_cal is error!!!");
	}
	dcxo_res_cal_l=find_dcxo_dpll_reg(dcxo_value,"dcxo_res_cal_l:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_res_cal_l=%x\n",dcxo_res_cal_l);
	if (dcxo_res_cal_l!=0xff||(dcxo_res_cal_l==0xff&&dcxo_default_valid==0)){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_res_cal_internal_l);
		dcxo_res_cal_internal_l=dcxo_res_cal_l;

		ret=atbm_reg_write_8(hw_priv,0x18,0x81);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_res_cal is error!!!");
		}
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_res_cal_internal_l);
	}else if (dcxo_res_cal_l==0xff && dcxo_default_valid){

		pinfo=&dcxo_default.info[1];
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_res_cal_internal_l);
		dcxo_res_cal_internal_l=pinfo->data;

		ret=atbm_reg_write_8(hw_priv,0x18,0x81);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_res_cal is error!!!");
		}
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_res_cal_internal_l);
	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb1);
       /*******************************************************************/
       	if(debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x11);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_res_cal_internal_l);
        	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_res_cal_internal_l=%x\n",dcxo_res_cal_internal_l);
	}
        /*******************************************************************/
	//dcxo_res_cal_2

	ret=atbm_reg_write_8(hw_priv,0x18,0x12);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_res_cal_internal_h is error!!!");
	}
	dcxo_res_cal_h=find_dcxo_dpll_reg(dcxo_value,"dcxo_res_cal_h:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_res_cal_h=%x\n",dcxo_res_cal_h);
	if (dcxo_res_cal_h!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_res_cal_internal_h);

		dcxo_res_cal_internal_h&=0xf8;
		dcxo_res_cal_internal_h|=dcxo_res_cal_h;

		atbm_reg_write_8(hw_priv,0x18,0x82);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_res_cal_internal_h);

	}else if(dcxo_res_cal_h==0xff && dcxo_default_valid){
		pinfo=&dcxo_default.info[2];

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_res_cal_internal_h);

		dcxo_res_cal_internal_h&=0xf8;
		dcxo_res_cal_internal_h|=pinfo->data;

		atbm_reg_write_8(hw_priv,0x18,0x82);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_res_cal_internal_h);
	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb2);
	/*******************************************************************/
	if (debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x12);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_res_cal_internal_h);
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_res_cal_internal_h=%x\n",dcxo_res_cal_internal_h);
	}
	/******************************************************************/

	//dcxo_dpll_clk_en

	ret=atbm_reg_write_8(hw_priv,0x18,0x12);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_dpll_clk_en_internal is error!!!");
	}
	dcxo_dpll_clk_en=find_dcxo_dpll_reg(dcxo_value,"dcxo_dpll_clk_en:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_dpll_clk_en=%x\n",dcxo_dpll_clk_en);

	if (dcxo_dpll_clk_en!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_dpll_clk_en_internal);
		dcxo_dpll_clk_en_internal&=0xef;
		dcxo_dpll_clk_en_internal|=dcxo_dpll_clk_en<<4;

		atbm_reg_write_8(hw_priv,0x18,0x82);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_dpll_clk_en_internal);
	}else if(dcxo_dpll_clk_en==0xff && dcxo_default_valid){

		pinfo=&dcxo_default.info[3];

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_dpll_clk_en_internal);
		dcxo_dpll_clk_en_internal&=0xef;
		dcxo_dpll_clk_en_internal|=pinfo->data<<4;

		atbm_reg_write_8(hw_priv,0x18,0x82);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_dpll_clk_en_internal);
	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb2);
        /*******************************************************************/
        if (debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x12);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_dpll_clk_en_internal);
        	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_dpll_clk_en_internal=%x\n",dcxo_dpll_clk_en_internal);
	}
        /*******************************************************************/
	//dcxo_trim
	ret=atbm_reg_write_8(hw_priv,0x18,0x12);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_trim_internal is error!!!");
	}
	dcxo_trim=find_dcxo_dpll_reg(dcxo_value,"dcxo_trim:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_trim=%x\n",dcxo_trim);

	if(dcxo_trim!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_trim_internal);

		dcxo_trim_internal&=0x7f;
		dcxo_trim_internal|=dcxo_trim<<7;

		atbm_reg_write_8(hw_priv,0x18,0x82);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_trim_internal);
	}else if(dcxo_trim==0xff && dcxo_default_valid){

		pinfo=&dcxo_default.info[4];
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_trim_internal);

		dcxo_trim_internal&=0x7f;
		dcxo_trim_internal|=pinfo->data<<7;

		atbm_reg_write_8(hw_priv,0x18,0x82);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_trim_internal);

	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb2);
       /*******************************************************************/
        if (debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x12);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_trim_internal);
        	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_trim_internal=%x\n",dcxo_trim_internal);
	}
        /*******************************************************************/
	//dcxo_trim_2
	ret=atbm_reg_write_8(hw_priv,0x18,0x13);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_trim_internal_2 is error!!!");
	}
	dcxo_trim_2=find_dcxo_dpll_reg(dcxo_value,"dcxo_trim:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_trim_2=%x\n",dcxo_trim_2);

	if (dcxo_trim_2!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_trim_internal_2);

		dcxo_trim_internal_2&=0xc0;
		dcxo_trim_internal_2|=dcxo_trim_2>>1;

		atbm_reg_write_8(hw_priv,0x18,0x83);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_trim_internal_2);
	}else if (dcxo_trim_2==0xff && dcxo_default_valid){
		pinfo=&dcxo_default.info[4];

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_trim_internal_2);

		dcxo_trim_internal_2&=0xc0;
		dcxo_trim_internal_2|=pinfo->data>>1;

		atbm_reg_write_8(hw_priv,0x18,0x83);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_trim_internal_2);
	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb3);
	/*******************************************************************/
        if (debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x13);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_trim_internal_2);
        	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_trim_internal=%x\n",dcxo_trim_internal_2);
	}
        /*******************************************************************/


	//dcxo_rfpll_clk_test

	ret=atbm_reg_write_8(hw_priv,0x18,0x13);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_rfpll_clk_test_internal is error!!!");
	}
	dcxo_rfpll_clk_test=find_dcxo_dpll_reg(dcxo_value,"dcxo_rfpll_clk_test:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_rfpll_clk_test=%x\n",dcxo_rfpll_clk_test);
	if (dcxo_rfpll_clk_test!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_rfpll_clk_test_internal);

		dcxo_rfpll_clk_test_internal&=0xbf;
		dcxo_rfpll_clk_test_internal|=dcxo_rfpll_clk_test<<6;

		atbm_reg_write_8(hw_priv,0x18,0x83);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_rfpll_clk_test_internal);
	}else if (dcxo_rfpll_clk_test==0xff && dcxo_default_valid){

		pinfo=&dcxo_default.info[5];

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_rfpll_clk_test_internal);

		dcxo_rfpll_clk_test_internal&=0xbf;
		dcxo_rfpll_clk_test_internal|=pinfo->data<<6;

		atbm_reg_write_8(hw_priv,0x18,0x83);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_rfpll_clk_test_internal);

	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb3);
       /*******************************************************************/
        if (debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x13);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_rfpll_clk_test_internal);
        	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_rfpll_clk_test_internal=%x\n",dcxo_rfpll_clk_test_internal);
	}
        /*******************************************************************/


	//dcxo_test_en
	ret=atbm_reg_write_8(hw_priv,0x18,0x13);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_test_en_internal is error!!!");
	}
	dcxo_test_en=find_dcxo_dpll_reg(dcxo_value,"dcxo_test_en:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_test_en=%x\n",dcxo_test_en);
	if (dcxo_test_en!=0xff){

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_test_en_internal);

		dcxo_test_en_internal&=0x7f;
		dcxo_test_en_internal|=dcxo_test_en<<7;

		atbm_reg_write_8(hw_priv,0x18,0x83);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_test_en_internal);
	}else if (dcxo_test_en ==0xff && dcxo_default_valid){

		pinfo=&dcxo_default.info[6];

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_test_en_internal);

		dcxo_test_en_internal&=0x7f;
		dcxo_test_en_internal|=pinfo->data<<7;

		atbm_reg_write_8(hw_priv,0x18,0x83);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_test_en_internal);

	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb3);
       /*******************************************************************/
        if (debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x13);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_test_en_internal);
        	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_test_en_internal=%x\n",dcxo_test_en_internal);
	}
        /*******************************************************************/

	//dcxo_iq_sw
	ret=atbm_reg_write_8(hw_priv,0x18,0x14);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_iq_sw_internal is error!!!");
	}
	dcxo_iq_sw=find_dcxo_dpll_reg(dcxo_value,"dcxo_iq_sw:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_iq_sw=%x\n",dcxo_iq_sw);
	if(dcxo_iq_sw!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_iq_sw_internal);

		dcxo_iq_sw_internal&=0xf8;
		dcxo_iq_sw_internal|=dcxo_iq_sw;

		atbm_reg_write_8(hw_priv,0x18,0x84);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_iq_sw_internal);
	}else if (dcxo_iq_sw==0xff && dcxo_default_valid){
		pinfo=&dcxo_default.info[7];

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_iq_sw_internal);

		dcxo_iq_sw_internal&=0xf8;
		dcxo_iq_sw_internal|=pinfo->data;

		atbm_reg_write_8(hw_priv,0x18,0x84);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_iq_sw_internal);

	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb4);
       /*******************************************************************/
        if (debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x14);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_iq_sw_internal);
        	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_iq_sw_internal=%x\n",dcxo_iq_sw_internal);
	}
        /*******************************************************************/

	//dcxo_ictrl
	ret=atbm_reg_write_8(hw_priv,0x18,0x14);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_ictrl_internal is error!!!");
	}
	dcxo_ictrl=find_dcxo_dpll_reg(dcxo_value,"dcxo_ictrl:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_ictrl=%x\n",dcxo_ictrl);
	if (dcxo_ictrl!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_ictrl_internal);

		dcxo_ictrl_internal&=0x07;
		dcxo_ictrl_internal|=dcxo_ictrl<<3;

		atbm_reg_write_8(hw_priv,0x18,0x84);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_ictrl_internal);
	}else if (dcxo_ictrl==0xff && dcxo_default_valid){
		pinfo=&dcxo_default.info[8];

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_ictrl_internal);

		dcxo_ictrl_internal&=0x07;
		dcxo_ictrl_internal|=pinfo->data<<3;

		atbm_reg_write_8(hw_priv,0x18,0x84);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_ictrl_internal);

	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb4);
 	/*******************************************************************/
    if (debugMode){
    	ret=atbm_reg_write_8(hw_priv,0x18,0x14);
        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_ictrl_internal);
    	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_ictrl_internal=%x\n",dcxo_ictrl_internal);
}
    /*******************************************************************/

	//dcxo_ictrl_1
	dcxo_ictrl_2=find_dcxo_dpll_reg(dcxo_value,"dcxo_ictrl:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_ictrl_2=%x\n",dcxo_ictrl_2);
	if(dcxo_ictrl_2!=0xff){
		ret=atbm_reg_write_8(hw_priv,0x18,0x15);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_ictrl_internal is error!!!");
		}
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_ictrl_internal_2);

		dcxo_ictrl_internal_2&=0xfe;
		dcxo_ictrl_internal_2|=dcxo_ictrl_2>>5;

		atbm_reg_write_8(hw_priv,0x18,0x85);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_ictrl_internal_2);
	}else if (dcxo_ictrl_2==0xff && dcxo_default_valid){

		pinfo=&dcxo_default.info[8];
		ret=atbm_reg_write_8(hw_priv,0x18,0x15);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_ictrl_internal is error!!!");
		}
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_ictrl_internal_2);

		dcxo_ictrl_internal_2&=0xfe;
		dcxo_ictrl_internal_2|=pinfo->data>>5;

		atbm_reg_write_8(hw_priv,0x18,0x85);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_ictrl_internal_2);


	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb5);
	/*******************************************************************/
        if (debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x15);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_ictrl_internal_2);
        	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_ictrl_internal_2=%x\n",dcxo_ictrl_internal_2);
	}
        /*******************************************************************/


	//dcxo_model_sel
	ret=atbm_reg_write_8(hw_priv,0x18,0x15);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_model_sel_internal is error!!!");
	}
	dcxo_mode_sel=find_dcxo_dpll_reg(dcxo_value,"dcxo_mode_sel:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_model_sel=%x\n",dcxo_mode_sel);

	if (dcxo_mode_sel!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_model_sel_internal);

		dcxo_model_sel_internal&=0xf9;
		dcxo_model_sel_internal|=dcxo_mode_sel<<1;

		atbm_reg_write_8(hw_priv,0x18,0x85);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_model_sel_internal);
	}else if (dcxo_mode_sel==0xff && dcxo_default_valid){

		pinfo=&dcxo_default.info[9];
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_model_sel_internal);

		dcxo_model_sel_internal&=0xf9;
		dcxo_model_sel_internal|=pinfo->data<<1;

		atbm_reg_write_8(hw_priv,0x18,0x85);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_model_sel_internal);


	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb5);
        /*******************************************************************/
	if (debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x15);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_model_sel_internal);
        	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_model_sel_internal=%x\n",dcxo_model_sel_internal);
	}
        /*******************************************************************/


	//dcxo_iqcal_en
	ret=atbm_reg_write_8(hw_priv,0x18,0x15);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo_iqcal_en_internal is error!!!");
	}
	dcxo_iqcal_en=find_dcxo_dpll_reg(dcxo_value,"dcxo_iqcal_en:");

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_iqcal_en=%x\n",dcxo_iqcal_en);
	if(dcxo_iqcal_en!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_iqcal_en_internal);

		dcxo_iqcal_en_internal&=0xf7;
		dcxo_iqcal_en_internal|=dcxo_iqcal_en<<3;
		atbm_reg_write_8(hw_priv,0x18,0x85);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_iqcal_en_internal);
	}else if (dcxo_iqcal_en==0xff && dcxo_default_valid){

		pinfo=&dcxo_default.info[10];

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_iqcal_en_internal);

		dcxo_iqcal_en_internal&=0xf7;
		dcxo_iqcal_en_internal|=pinfo->data<<3;
		atbm_reg_write_8(hw_priv,0x18,0x85);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_iqcal_en_internal);

	}

	dcxo_ldo_byp=find_dcxo_dpll_reg(dcxo_value,"dcxo_ldo_byp:");
	if (dcxo_ldo_byp!=0xff){

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_ldo_byp_internal);

		dcxo_ldo_byp_internal&=0xef;
		dcxo_ldo_byp_internal|=dcxo_ldo_byp<<4;
		atbm_reg_write_8(hw_priv,0x18,0x85);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_ldo_byp_internal);

	}else if (dcxo_ldo_byp==0xff && dcxo_default_valid){
		pinfo=&dcxo_default.info[11];

		ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_ldo_byp_internal);

		dcxo_ldo_byp_internal&=0xef;
		dcxo_ldo_byp_internal|=pinfo->data<<4;
		atbm_reg_write_8(hw_priv,0x18,0x85);
		ret=atbm_reg_write_8(hw_priv,0x19,dcxo_ldo_byp_internal);

	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb5);
        /*******************************************************************/
        if (debugMode){
        	ret=atbm_reg_write_8(hw_priv,0x18,0x15);
	        ret=atbm_reg_read_8(hw_priv,0x19,&dcxo_iqcal_en_internal);
        	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************dcxo_ldo_byp&dcxo_iqcal_en internal=%x\n",dcxo_iqcal_en_internal);	//asic needed
	}
        /*******************************************************************/
	//sdio_dcxo_iso_en
	ret=atbm_reg_write_8(hw_priv,0x18,0x15);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"sdio_dcxo_iso_en_internal is error!!!");
	}
	sdio_dcxo_iso_en=find_dcxo_dpll_reg(dcxo_value,"sdio_dcxo_iso_en:");
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************sdio_dcxo_iso_en=%x\n",sdio_dcxo_iso_en);
	if (sdio_dcxo_iso_en!=0xff){
		ret=atbm_reg_read_8(hw_priv,0x19,&sdio_dcxo_iso_en_internal);

		sdio_dcxo_iso_en_internal&=0xdf;
		sdio_dcxo_iso_en_internal|=sdio_dcxo_iso_en<<5;

		atbm_reg_write_8(hw_priv,0x18,0x85);
		ret=atbm_reg_write_8(hw_priv,0x19,sdio_dcxo_iso_en_internal);
	}else if (sdio_dcxo_iso_en==0xff && dcxo_default_valid){
		pinfo=&dcxo_default.info[12];

		ret=atbm_reg_read_8(hw_priv,0x19,&sdio_dcxo_iso_en_internal);

		sdio_dcxo_iso_en_internal&=0xdf;
		sdio_dcxo_iso_en_internal|=pinfo->data<<5;

		atbm_reg_write_8(hw_priv,0x18,0x85);
		ret=atbm_reg_write_8(hw_priv,0x19,sdio_dcxo_iso_en_internal);
	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xb5);
	    /*******************************************************************/
	    if (debugMode){
		ret=atbm_reg_write_8(hw_priv,0x18,0x15);
	    ret=atbm_reg_read_8(hw_priv,0x19,&sdio_dcxo_iso_en_internal);
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"*************sdio_dcxo_iso_en_internal=%x\n",sdio_dcxo_iso_en_internal);
		}
	        /*******************************************************************/
	//dcxo config finished
	atbm_reg_write_8(hw_priv,0x18,0xb5);

	return 0;
}

#define DPLL_REG_READ(start_bit,value) do { \
	ret=atbm_reg_write_8(hw_priv,0x18,0x50 + start_bit/8); \
	if (ret<0){\
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dpll_%d_bit is error!!!",start_bit); \
	}\
	ret=atbm_reg_read_8(hw_priv,0x19,&value);\
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"**read reg%d bit[%d] value 0x%x\n", start_bit/8,start_bit,value);\
}while(0)

#define DPLL_REG_WRITE(start_bit,value) do { \
		atbm_reg_write_8(hw_priv,0x18,0xc0 + start_bit/8);		 \
		ret=atbm_reg_write_8(hw_priv,0x19,value); \
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"**write reg%2d bit[%d] value 0x%x\n", start_bit/8,start_bit,value);\
	}while(0)


#define DPLL_CHECK_DEFAULT_NAME(dpll_data_val,dpll_reg_val,start_bit,end_bit,name) do { \
			u8 find_buf[32];\
			memset(find_buf,0,32);\
			sprintf(find_buf,"%s:",name); \
			dpll_data_val=find_dcxo_dpll_reg(dpll_value,find_buf); \
			if(dpll_data_val!=0xff) {\
				atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"**insmod**%s=%x,BIT(%d:%d)\n",name,dpll_data_val,end_bit,start_bit);\
			}\
			if((dpll_data_val==0xff)&&(dpll_default_valid)){ \
			if((pinfo->data!=0xff)&&(dpll_default_valid)){ \
				dpll_data_val = pinfo->data; \
			} \
		} \
	}while(0)

#define DPLL_CHANGE_DEFAULT_NAME(dpll_data_val,dpll_reg_val,start_bit,end_bit,name) do { \
		if(dpll_data_val!=0xff){ \
			u8 regmask =0; \
			u8 startbit = start_bit%8; \
			u8 endbit = end_bit%8; \
			regmask = ~(BIT(startbit)-1);\
			regmask &=(BIT(endbit)-1)|BIT(endbit); \
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"**set**%s=%x,BIT(%d:%d), reg= 0x%x ",name,dpll_data_val,end_bit,start_bit,dpll_reg_val);\
			dpll_reg_val&=~regmask; \
			dpll_reg_val|=(dpll_data_val<<startbit)&regmask; \
		    atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"**change reg 0x%x\n",dpll_reg_val);\
		}\
	}while(0)
 


#define DPLL_REG_READ_DBG_NAME(dpll_reg_val,start_bit,end_bit,name) do { \
			u8 regmask =0;\
			u8 startbit = 0; \
			u8 endbit = 0; \
			ret=atbm_reg_write_8(hw_priv,0x18,0xf0+ start_bit/8); \
			ret=atbm_reg_write_8(hw_priv,0x18,0x40+ start_bit/8);\
			ret=atbm_reg_read_8(hw_priv,0x19,&dpll_reg_val);\
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"****read*40***reg%2d**=%x\n",start_bit/8,dpll_reg_val);\
			ret=atbm_reg_write_8(hw_priv,0x18,0x50+ start_bit/8);\
			ret=atbm_reg_read_8(hw_priv,0x19,&dpll_reg_val);\
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"***read*50****dpll_regbit%2d_%2d=%x\n",start_bit,end_bit,dpll_reg_val);\
			regmask =0;\
			startbit = start_bit%8;\
			endbit = end_bit%8;\
			regmask = ~(BIT(startbit)-1);\
			regmask &=(BIT(endbit)-1)|BIT(endbit);\
			dpll_reg_val&=regmask; \
			dpll_reg_val =(dpll_reg_val>>startbit);\
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"****check***%s BIT[%d~%d]=%x\n",name,start_bit,end_bit,dpll_reg_val);\
			}while(0)


struct reg_info {
	u8 data;
	u8 start_bit;
	u8 end_bit;
	u8 valid;
	char *name;
};
#define DPLL_REG_MAX  32
struct dpll_reg {
	struct reg_info info[DPLL_REG_MAX];
};
#define DPLL_INIT_DEFAULT(reg_name,startbit,endbit,val) {\
	dpll_default.info[i].start_bit = startbit;\
	dpll_default.info[i].end_bit = endbit;\
	dpll_default.info[i].data = val;\
	dpll_default.info[i].name = #reg_name;\
	i++;\
};
struct dpll_reg dpll_default;

static void atbm_dpll_read_default_value(struct atbm_common *hw_priv,const char * test)
{
	int ret;
	int i;
	u8 dpll_regdata;
	struct reg_info *pinfo;

	for(i=0;i<sizeof(struct dpll_reg)/sizeof(struct reg_info);i++){
		pinfo = &dpll_default.info[i];
		if (debugMode){
			DPLL_REG_READ_DBG_NAME(dpll_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
		}
	}
}
int  atbm_dpll_init_default(int prjType,int dpllClock)
{
	int i=0;
	DPLL_INIT_DEFAULT(dpll_ldo_trim,11,13,0x0);
	DPLL_INIT_DEFAULT(dpll_ldo_test,15,15,0x0);
	DPLL_INIT_DEFAULT(dpll_afc_restart_en,16,16,0x0);
	DPLL_INIT_DEFAULT(dpll_clk24_pd,18,18,0x0);
	DPLL_INIT_DEFAULT(dpll_en_160b,19,19,0x0);
	DPLL_INIT_DEFAULT(dpll_en_rc160,20,20,0x0);
	DPLL_INIT_DEFAULT(dpll_en_320,21,21,0x0);
	DPLL_INIT_DEFAULT(dpll_en_480,22,22,0x0);
	DPLL_INIT_DEFAULT(dpll_en_960,23,23,0x0);
	DPLL_INIT_DEFAULT(dpll_close_pll_loop,24,24,0x0);
	DPLL_INIT_DEFAULT(dpll_dither_sel,25,25,0x0);
	DPLL_INIT_DEFAULT(dpll_div_edge_sele,26,26,0x0);
	DPLL_INIT_DEFAULT(dpll_en_dither,27,27,0x1);
	if (dpllClock==DPLL_CLOCK_26M){
		DPLL_INIT_DEFAULT(dpll_en_sdm,28,28,0x1);
	}else{
		DPLL_INIT_DEFAULT(dpll_en_sdm,28,28,0x0);
	}
	DPLL_INIT_DEFAULT(dpll_fn_afc_done_en,29,29,0x1);
	DPLL_INIT_DEFAULT(dpll_sdm_edge_sele,34,34,0x1);
	DPLL_INIT_DEFAULT(dpll_vco_tune_manual_en,35,35,0x0);
	if (dpllClock==DPLL_CLOCK_26M){
		DPLL_INIT_DEFAULT(dpll_nint,36,39,0x9);
		DPLL_INIT_DEFAULT(dpll_nint_2,40,43,0x4);
	}else if(dpllClock==DPLL_CLOCK_24M){
		DPLL_INIT_DEFAULT(dpll_nint,36,39,0x0);
		DPLL_INIT_DEFAULT(dpll_nint_2,40,43,0x8);
	}else{
		DPLL_INIT_DEFAULT(dpll_nint,36,39,0x0);
		DPLL_INIT_DEFAULT(dpll_nint_2,40,43,0x3);
	}
	DPLL_INIT_DEFAULT(dpll_fn_afc_bits,44,46,0x3);
	DPLL_INIT_DEFAULT(dpll_pc_vctrl,47,47,0x1);
	DPLL_INIT_DEFAULT(dpll_pc_vctrl_2,48,49,0x1);
	DPLL_INIT_DEFAULT(dpll_vco_bctrl,50,51,0x0);
	DPLL_INIT_DEFAULT(dpll_ctrl_cp_i,52,55,0x4);
	DPLL_INIT_DEFAULT(dpll_ctrl_cp_i_2,56,57,0x0);
	DPLL_INIT_DEFAULT(dpll_vco_ctrl_bits_manual,58,63,0x20);
	if (dpllClock==DPLL_CLOCK_26M){
		DPLL_INIT_DEFAULT(dpll_nfrac,64,71,0x89);
		DPLL_INIT_DEFAULT(dpll_nfrac_2,72,79,0x9d);
		DPLL_INIT_DEFAULT(dpll_nfrac_3,80,87,0xd8);
	}else{
		DPLL_INIT_DEFAULT(dpll_nfrac,64,71,0x0);
		DPLL_INIT_DEFAULT(dpll_nfrac_2,72,79,0x0);
		DPLL_INIT_DEFAULT(dpll_nfrac_3,80,87,0x0);
	}
	DPLL_INIT_DEFAULT(sdio_dpll_iso_en,88,88,0x0);
	//these bits is not used by apolloB,so it is not need to add apolloC 
	DPLL_INIT_DEFAULT(dpll_sel_external,92,92,0x0);
	DPLL_INIT_DEFAULT(dpll_test_pd,93,93,0x1);
	return 0;
}

int atbm_dpll_test_value(struct atbm_common *hw_priv,const char * dpll_value,int prjType,int dpll_clock)
{
	int ret;
	u8 dpll_regdata;
	u8 dpll_tmp;
	u8 dpll_default_valid= 1;
	int i = 0;
	struct reg_info *pinfo;
	//u8 dpll_regdata_tbl[96/8];
	atbm_dpll_init_default(prjType,dpll_clock);
	if(strstr(dpll_value,"dpll"))
		dpll_default_valid = 0;
	for(i=0;i<96/8;i++){
		DPLL_REG_READ(i*8,dpll_regdata_tbl[i]);
	}
	debugMode=enable_debugMode(dpll_value,"debugMode:");
	for(i=0;i<sizeof(struct dpll_reg)/sizeof(struct reg_info);i++){
		pinfo = &dpll_default.info[i];
		dpll_regdata = dpll_regdata_tbl[pinfo->start_bit/8];
		DPLL_CHECK_DEFAULT_NAME(dpll_tmp,dpll_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
		DPLL_CHANGE_DEFAULT_NAME(dpll_tmp,dpll_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
		dpll_regdata_tbl[pinfo->start_bit/8] = dpll_regdata;
		if((pinfo->start_bit == 36)&&(dpll_tmp != 0xff)){
			pinfo = &dpll_default.info[i+1];
			dpll_regdata = dpll_regdata_tbl[pinfo->start_bit/8];
			dpll_tmp = dpll_tmp >> 4;
			DPLL_CHANGE_DEFAULT_NAME(dpll_tmp,dpll_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
			dpll_regdata_tbl[pinfo->start_bit/8] = dpll_regdata;
		}
		if((pinfo->start_bit == 47)&&(dpll_tmp != 0xff)){
			pinfo = &dpll_default.info[i+1];
			dpll_regdata = dpll_regdata_tbl[pinfo->start_bit/8];
			dpll_tmp = dpll_tmp >> 1;
			DPLL_CHANGE_DEFAULT_NAME(dpll_tmp,dpll_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
			dpll_regdata_tbl[pinfo->start_bit/8] = dpll_regdata;
		}
		if((pinfo->start_bit == 52)&&(dpll_tmp != 0xff)){
			pinfo = &dpll_default.info[i+1];
			dpll_regdata = dpll_regdata_tbl[pinfo->start_bit/8];
			dpll_tmp = dpll_tmp >> 4;
			DPLL_CHANGE_DEFAULT_NAME(dpll_tmp,dpll_regdata,pinfo->start_bit,pinfo->end_bit,pinfo->name);
			dpll_regdata_tbl[pinfo->start_bit/8] = dpll_regdata;
		}

	}

	for(i=0;i<96/8;i++){
		DPLL_REG_WRITE(i*8,dpll_regdata_tbl[i]);
	}
	//dpll config finish
	ret=atbm_reg_write_8(hw_priv,0x18,0xfb);

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"***dpll config finish \n");

	mdelay(100);
	return 0;
}


#define DCXO_READ_CMD 0x10
#define DCXO_WRITE_CMD 0x80
#define DCXO_WRITE_FINISH_CMD 0xB0

#define DCXO_LDO_PUP_POSITION 21
#define DCXO_CFG_DONE_POSITION 22
#define DCXO_VAL_RETRY_POSITION 23
#define DCXO_CFG_VAL_POSITION 24
#define DCXO_START_POSITION 25
#define DCXO_DIG_CLOCK_EN_POSITION 26
#define DCXO_DETECT_EN_POSITION 27

#define DCXO_INIT_TIME(reg_name,startbit,endbit,val,index) \
	dcxo_default.info[index].start_bit = startbit;\
	dcxo_default.info[index].end_bit = endbit;\
	dcxo_default.info[index].data = val;\
	dcxo_default.info[index].name = #reg_name;
static void atbm_dcxo_time_reg_apolloc(void)
{
	DCXO_INIT_TIME(dcxo_ldo_pup,24,24,0x0,DCXO_LDO_PUP_POSITION)
	DCXO_INIT_TIME(dcxo_cfg_done,49,49,0x0,DCXO_CFG_DONE_POSITION)
	DCXO_INIT_TIME(dcxo_val_retry,48,48,0x0,DCXO_VAL_RETRY_POSITION)
	DCXO_INIT_TIME(dcxo_cfg_val,50,50,0x0,DCXO_CFG_VAL_POSITION)
	DCXO_INIT_TIME(dcxo_start,28,28,0x0,DCXO_START_POSITION)
	DCXO_INIT_TIME(dcxo_dig_clk_en,12,12,0x0,DCXO_DIG_CLOCK_EN_POSITION)
	DCXO_INIT_TIME(dcxo_detect_en,11,11,0x0,DCXO_DETECT_EN_POSITION)
}
static void atbm_dcxo_time_reg(void)
{
	DCXO_INIT_TIME(dcxo_ldo_pup,21,21,0x0,DCXO_LDO_PUP_POSITION)
	DCXO_INIT_TIME(dcxo_cfg_done,47,47,0x0,DCXO_CFG_DONE_POSITION)
	DCXO_INIT_TIME(dcxo_val_retry,46,46,0x0,DCXO_VAL_RETRY_POSITION)
	DCXO_INIT_TIME(dcxo_cfg_val,48,48,0x0,DCXO_CFG_VAL_POSITION)
	DCXO_INIT_TIME(dcxo_start,22,22,0x0,DCXO_START_POSITION)
	DCXO_INIT_TIME(dcxo_dig_clk_en,19,19,0x0,DCXO_DIG_CLOCK_EN_POSITION)
	DCXO_INIT_TIME(dcxo_detect_en,4,4,0x0,DCXO_DETECT_EN_POSITION)
}
static int dcxo_signal_config(struct atbm_common*hw_priv,char *signalName,u8 startBit,u8 endBit,u8 value)
{
	int ret;
	u8 regmask =0;
	u8 signalValue=0;;
	ret=atbm_reg_write_8(hw_priv,0x18,DCXO_READ_CMD+startBit/8);/*16-23bit*/
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"line=%d:signalName=%s",__LINE__,signalName);
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&signalValue);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"line=%d:signalName=%s",__LINE__,signalName);
	}

	ret=atbm_reg_write_8(hw_priv,0x18,DCXO_WRITE_CMD+startBit/8);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"line=%d:signalName=%s",__LINE__,signalName);
	}
	regmask=~((1<<startBit%8)-1);
	regmask&=((1<<endBit%8)-1)|(1<<endBit%8);
	signalValue&=~regmask;
	signalValue|=(value<<startBit%8)&regmask;
	ret =atbm_reg_write_8(hw_priv,0x19,signalValue);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"line=%d:signalName=%s",__LINE__,signalName);
	}

	ret =atbm_reg_write_8(hw_priv,0x18,DCXO_WRITE_FINISH_CMD+startBit/8);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"line=%d:signalName=%s",__LINE__,signalName);
	}
	return ret;
}
static int atbm_wait_dcxo_succ_fail(struct atbm_common*hw_priv,u8 successBit,u8 failBit)
{
	int ret=0;
	u8 Dcxo_val_suc_fail;
	while(1){
		ret=atbm_reg_write_8(hw_priv,0x18,0x00+successBit/8);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dpll reg error",__func__);
		}
		ret =atbm_reg_read_8(hw_priv,0x19,&Dcxo_val_suc_fail);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dpll reg error",__func__);
		}
		/*success or fail*/
		if ((Dcxo_val_suc_fail&BIT(failBit))||(Dcxo_val_suc_fail&BIT(successBit))){

			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:Start atbm_config_dcxo\n",Dcxo_val_suc_fail);
			break;
		}

	}
	return ret;
}
static int atbm_dcxo_reg_realVal_to_sdioVal(struct atbm_common*hw_priv)
{
	int init_dcxo;
	int ret;
	u8 Dcxo_init_dcxo_real;
	u8 Dcxo_init_dcxo_sdio;
	for (init_dcxo=0x0;init_dcxo<0xc;init_dcxo++)
	{
		/*1.0 read real signal reg cmd*/
		ret=atbm_reg_write_8(hw_priv,0x18,0x00+init_dcxo);/* read 0-96bit*/
		if (ret<0)
		{
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read action init_reg cmd error\n",__func__);

		}
		/*2.0 read real signal reg value*/
		ret =atbm_reg_read_8(hw_priv,0x19,&Dcxo_init_dcxo_real);
		if (ret<0)
		{
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dcxo_init_dcxo_real value error\n",__func__);

		}
		/*3.0 write the sdio reg cmd*/
		ret=atbm_reg_write_8(hw_priv,0x18,0x80+init_dcxo);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:write action Dcxo_init_dcxo_sdio cmd error\n",__func__);
		}
		/*4.0 write the real signal to sdio reg*/
		Dcxo_init_dcxo_sdio=Dcxo_init_dcxo_real;
		ret =atbm_reg_write_8(hw_priv,0x19,Dcxo_init_dcxo_sdio);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dcxo_init_dcxo_sdio error",__LINE__);
		}
		/*5.0 write finish cmd*/
  		ret =atbm_reg_write_8(hw_priv,0x18,0xb0+init_dcxo);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dcxo_init_dcxo_sdio error",__LINE__);
		}
	}
	return ret;

}
static int atbm_wait_dcxo_idel(struct atbm_common*hw_priv,u8 successBit,u8 failBit)
{
	int ret;
	u8 Dcxo_val_suc_fail;
	while(1){
		ret=atbm_reg_write_8(hw_priv,0x18,0x10+successBit/8);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dpll reg error",__func__);
		}
		ret =atbm_reg_read_8(hw_priv,0x19,&Dcxo_val_suc_fail);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dpll reg error",__func__);
		}
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x,Dcxo_val_suc_fail---------------------\n",Dcxo_val_suc_fail);
		if (((Dcxo_val_suc_fail&BIT(failBit))==0)&&((Dcxo_val_suc_fail&BIT(successBit))==0))
		{
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:start atbm_config_dpll-----------------\n",Dcxo_val_suc_fail);
			break;
		}
	}
	return ret;

}
static int atbm_wait_dcxo_success(struct atbm_common*hw_priv,u8 successBit,u8 failBit)
{
	int ret ;	
	u8 Dcxo_val_suc_fail;
	while(1){
		ret=atbm_reg_write_8(hw_priv,0x18,0x00+successBit/8);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dcxo_work_s & dcxo_work_fail error",__LINE__);
		}
		ret =atbm_reg_read_8(hw_priv,0x19,&Dcxo_val_suc_fail);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read Dcxo_val_suc_fail & Dcxo_val_suc_fail error",__LINE__);
		}

		//atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:Start Dcxo_val_suc_fail\n",Dcxo_val_suc_fail);
		/*success or fail*/
		if ((Dcxo_val_suc_fail&BIT(failBit))==8){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo calibration fail!!!\n");
			dcxo_fail=1;
		}
		if ((Dcxo_val_suc_fail&BIT(successBit))==4){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dcxo calibration success!!!\n");
			break;
		}
	}
	return ret;
}
int atbm_config_dcxo(struct atbm_common *hw_priv,char *value,int prjType,int dcxoType,int dpllClock)
{
	int index;
	struct dcxo_reg_info *pinfo;
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"Start atbm_config_dcxo++++++=\n");
	/*The First step ,wait for Dpll success or fail*/
	/*wait for success or fail
	success bit is 2& fail bit is 3
	*/
	atbm_wait_dcxo_succ_fail(hw_priv,2,3);
	/*read real value from asic & write real value to sdio*/
	atbm_dcxo_reg_realVal_to_sdioVal(hw_priv);
	if (prjType==APOLLO_C){
		/*start config dcxo test value*/
		atbm_dcxo_test_value_apolloc(hw_priv,value,dpllClock);
		/*dcxo's time reg init*/
		atbm_dcxo_time_reg_apolloc();
	}else{
		atbm_dcxo_test_value(hw_priv,value,dpllClock);
		/*dcxo's time reg init*/
		atbm_dcxo_time_reg();
	}
dcxo_again:
	/*dcxo_ldo_pup ==0 /dcxo_cfg_done====0/ dcxo_val_retry ==0/dcxo_cfg_val====0/ dcxo_start====0 /dcxo_dig_clk_en====0*/
	for(index=DCXO_LDO_PUP_POSITION;index<DCXO_DETECT_EN_POSITION+1;index++)
	{
		pinfo=&dcxo_default.info[index];
		dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,pinfo->data);
	}
	/*The second step */
	/*set register value for timming--- Dcxo_val_retry ==1*/
	pinfo = &dcxo_default.info[DCXO_VAL_RETRY_POSITION];
	dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,~pinfo->data);
	
	/*wait for dcxo idel success bit is 2& fail bit is 3*/
	atbm_wait_dcxo_idel(hw_priv,2,3);

	/*set register value for timming---dcxo cfg vld==1 */
    pinfo = &dcxo_default.info[DCXO_CFG_VAL_POSITION];
    dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,~pinfo->data);
	
	/*set register value for timming--- Dcxo_val_retry===0*/
	pinfo = &dcxo_default.info[DCXO_VAL_RETRY_POSITION];
	dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,pinfo->data);

	if (dcxoType==CRYSTAL_MODE)
	{
		/*Crystal mode DCXO*/
		/* T1 wait for 10us*/
		delay_sdio(200*100);

		/*set register value for timming---Dcxo_ldo_pup==1 */
		pinfo = &dcxo_default.info[DCXO_LDO_PUP_POSITION];
		dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,~pinfo->data);
		/*T2 wait for */
		/*dcxo_start==1*/
		delay_sdio(200*50);
		pinfo = &dcxo_default.info[DCXO_START_POSITION];
		dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,~pinfo->data);

		delay_sdio(6000*50);
		/*T3 wait */
		/*set register value for timming---dcxo_dig_clk_en==1*/
		pinfo = &dcxo_default.info[DCXO_DIG_CLOCK_EN_POSITION];
		dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,~pinfo->data);
	}
	else{
		/*External mode DCXO????*/
		/*dcxo_start==0*/
		pinfo = &dcxo_default.info[DCXO_START_POSITION];
		dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,pinfo->data);
		/* T1 wait for 10us*/
		delay_sdio(100);

		/*set register value for timming---Dcxo_ldo_pup==1 */
		pinfo = &dcxo_default.info[DCXO_LDO_PUP_POSITION];
		dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,~pinfo->data);
		/*T2 wait for */
		/*dcxo_detect_en==1*/
		pinfo = &dcxo_default.info[DCXO_DETECT_EN_POSITION];
		dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,~pinfo->data);

		delay_sdio(6000*50);
		/*T3 wait */
		/*set register value for timming---dcxo_dig_clk_en==1*/
		pinfo = &dcxo_default.info[DCXO_DIG_CLOCK_EN_POSITION];
		dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,~pinfo->data);
	}
	delay_sdio(100);
	/*set register value for timming---dcxol_cfg_done==1*/
	pinfo = &dcxo_default.info[DCXO_CFG_DONE_POSITION];
	dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,~pinfo->data);
	/*The third step,wait for success fail state*/
	atbm_wait_dcxo_success(hw_priv,2,3);
	if (dcxo_fail){
		dcxo_fail=0;
		goto dcxo_again;
	}
	/*dcxo_config end-----print config value*/
#ifdef READ_DCXO_VALUE
	atbm_dcxo_read_default_value(hw_priv,value);
#endif
	return 0;
}
#if defined(TEST_DPLL_CONFIG) || defined(atbm_dpll_reg_get_bit)
static void atbm_smu_reg_clear_bit(struct atbm_common *hw_priv,u32* signalValue,u8 startBit,u8 endBit)
{
	u32 regmask=0;
	regmask=~((1<<startBit)-1);
	regmask&=((1<<endBit)-1)|(1<<endBit);
	*signalValue&=~regmask;
}
static u8 atbm_dpll_reg_get_bit(struct atbm_common *hw_priv,u8 *signalValue,u8 startBit,u8 endBit)
{
	u8 regmask=0;
	u8 temvalue =*signalValue;
	regmask=~((1<<startBit%8)-1);
	regmask&=((1<<endBit%8)-1)|(1<<endBit%8);
	temvalue&=regmask;
	temvalue=temvalue>>startBit%8;
	return temvalue;
}
#endif
#ifdef TEST_DPLL_CONFIG
static int atbm_write_dpll_value_to_smu(struct atbm_common *hw_priv,u32 register_addr)
{
	int ret;
	u8 getData=0;
	u32 sys_dpll_smu_reg;
	ret=atbm_ahb_read_32(hw_priv,register_addr,&sys_dpll_smu_reg);
	printk(" register_addr=%x,default_value=%x\n",register_addr,sys_dpll_smu_reg);
	switch (register_addr){
		case 0x16101018:
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,0,2);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[1],11,13);
			sys_dpll_smu_reg|=getData;
	
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,8,13);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[7],58,63);
			sys_dpll_smu_reg|=getData<<8;
			
			printk("register_addr=%x,change_value=%x\n",register_addr,sys_dpll_smu_reg);
			break;
		case 0x1610101c:
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,0,5);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[6],52,55);
			sys_dpll_smu_reg|=getData;
			
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[7],56,57);
			sys_dpll_smu_reg|=getData<<4;
			
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,8,9);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[6],50,51);
			sys_dpll_smu_reg|=getData<<4;
			
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,16,18);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[5],47,47);
			sys_dpll_smu_reg|=getData<<16;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[6],48,49);
			sys_dpll_smu_reg|=getData<<17;

					
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,24,26);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[5],44,46);
			sys_dpll_smu_reg|=getData<<24;
			printk("register_addr=%x,change_value=%x\n",register_addr,sys_dpll_smu_reg);
			break;
			
		case 0x16101020:
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,0,7);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[4],36,39);
			sys_dpll_smu_reg|=getData;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[5],40,43);
			sys_dpll_smu_reg|=getData<<4;
			
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,8,31);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[8],64,71);
			sys_dpll_smu_reg|=getData<<8;
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,16,23);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[9],72,79);
			sys_dpll_smu_reg|=getData<<16;
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,24,31);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[10],80,87);
			sys_dpll_smu_reg|=getData<<24;
			printk("register_addr=%x,change_value=%x\n",register_addr,sys_dpll_smu_reg);
			break;
		case 0x16101024:
			atbm_smu_reg_clear_bit(hw_priv,&sys_dpll_smu_reg,0,15);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[4],35,35);
			sys_dpll_smu_reg|=getData;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[4],34,34);
			sys_dpll_smu_reg|=getData<<1;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[3],29,29);
			sys_dpll_smu_reg|=getData<<2;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[3],28,28);
			sys_dpll_smu_reg|=getData<<3;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[3],27,27);
			sys_dpll_smu_reg|=getData<<4;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[3],26,26);
			sys_dpll_smu_reg|=getData<<5;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[3],25,25);
			sys_dpll_smu_reg|=getData<<6;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[3],24,24);
			sys_dpll_smu_reg|=getData<<7;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[2],23,23);
			sys_dpll_smu_reg|=getData<<8;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[2],22,22);
			sys_dpll_smu_reg|=getData<<9;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[2],21,21);
			sys_dpll_smu_reg|=getData<<10;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[2],20,20);
			sys_dpll_smu_reg|=getData<<11;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[2],19,19);
			sys_dpll_smu_reg|=getData<<12;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[2],18,18);
			sys_dpll_smu_reg|=getData<<13;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[2],16,16);
			sys_dpll_smu_reg|=getData<<14;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dpll_regdata_tbl[1],15,15);
			sys_dpll_smu_reg|=getData<<15;
			printk("register_addr=%x,change_value=%x\n",register_addr,sys_dpll_smu_reg);
			break;
		default:
			printk("invalid regaddr=%x\n",register_addr);
			break;
		}
	
	ret=atbm_ahb_write_32(hw_priv,register_addr,sys_dpll_smu_reg);
	return 0;
}
#endif
#ifdef TEST_DCXO_CONFIG
static int atbm_write_dcxo_value_to_smu(struct atbm_common *hw_priv,u32 register_addr)
{
	int ret;
	u8 getData=0;
	u32 sys_dcxo_smu_reg;
	ret=atbm_ahb_read_32(hw_priv,register_addr,&sys_dcxo_smu_reg);
	printk(" register_addr=%x,default_value=%x\n",register_addr,sys_dcxo_smu_reg);
	switch (register_addr){
		case 0x1610100c:
			/*smu dcxo trim*/
			atbm_smu_reg_clear_bit(hw_priv,&sys_dcxo_smu_reg,0,21);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[3],30,31);
			sys_dcxo_smu_reg|=getData;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[4],32,35);
			sys_dcxo_smu_reg|=getData<<2;

			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[1],14,15);
			sys_dcxo_smu_reg|=getData<<6;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[2],16,18);
			sys_dcxo_smu_reg|=getData<<8;

			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[4],36,39);
			sys_dcxo_smu_reg|=getData<<11;
			
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[5],40,46);
			sys_dcxo_smu_reg|=getData<<15;
			printk("register_addr=%x,change_value=%x\n",register_addr,sys_dcxo_smu_reg);
			break;
		case 0x16101010:
			/*smu dcxo ctrl*/
			atbm_smu_reg_clear_bit(hw_priv,&sys_dcxo_smu_reg,0,26);
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[3],29,29);
			sys_dcxo_smu_reg|=getData;
		
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[3],27,27);
			sys_dcxo_smu_reg|=getData<<1;
			
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[2],21,21);
			sys_dcxo_smu_reg|=getData<<2;			

			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[2],19,19);
			sys_dcxo_smu_reg|=getData<<3;

			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[1],13,13);
			sys_dcxo_smu_reg|=getData<<4;
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[2],23,23);
			sys_dcxo_smu_reg|=getData<<6;
			
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[2],22,22);
			sys_dcxo_smu_reg|=getData<<7;
			
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[2],20,20);
			sys_dcxo_smu_reg|=getData<<8;
			
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[0],6,7);
			sys_dcxo_smu_reg|=getData<<9;
			
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[1],8,10);
			sys_dcxo_smu_reg|=getData<<11;
			
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[0],5,5);
			sys_dcxo_smu_reg|=getData<<14;
			
			getData=atbm_dpll_reg_get_bit(hw_priv,&dcxo_regdata_tbl[0],4,4);
			sys_dcxo_smu_reg|=getData<<15;
			printk("register_addr=%x,change_value=%x\n",register_addr,sys_dcxo_smu_reg);
			break;
		default:
			printk("dcxo reg is invalid address=%x\n",register_addr);
			break;
	}
	ret=atbm_ahb_write_32(hw_priv,register_addr,sys_dcxo_smu_reg);
	return 0;
}
#endif
void atbm_set_config_to_smu_apolloB(struct atbm_common *hw_priv,int dpllClock)
{
	u32 sys_dcxo_ictrl_trim;
	u32 sys_dpll_ldo_trim;
	u32 sys_dpll_pc_vctrl;
	u32 sys_dpll_nint_nfrac;
	u32 sys_dpll_close_pll_loop;
	u32 sys_dpll_en_sdm;
	int ret;

	struct dcxo_reg_info *pinfo;
	
	struct reg_info *dpllinfo;
	
	/*The first step:dcxo changed value write to smu*/

	/*sys_dcxo_ictrl*/
	ret=atbm_ahb_read_32(hw_priv,SMU_DCXO_TRIM_ADDR,&sys_dcxo_ictrl_trim);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant read sys_dcxo_ictrl_trim\n",__func__);
	 }
	sys_dcxo_ictrl_trim&=~0xFFF8;
	pinfo=&dcxo_default.info[8];
	sys_dcxo_ictrl_trim|=pinfo->data<<10;
	pinfo=&dcxo_default.info[4];
	sys_dcxo_ictrl_trim|=pinfo->data<<3;
	ret=atbm_ahb_write_32(hw_priv,SMU_DCXO_TRIM_ADDR,sys_dcxo_ictrl_trim);
	
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant write sys_dcxo_trim\n",__func__);
	 }

	/*The first step: dpll changed value write to smu*/
	/*sys_dpll_ldo_trim*/
	ret=atbm_ahb_read_32(hw_priv,SMU_DPLL_PARAM_1_ADDR,&sys_dpll_ldo_trim);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant read sys_dpll_ldo_trim\n",__func__);
	 }
	
	dpllinfo = &dpll_default.info[0];
	sys_dpll_ldo_trim&=~0x7;
	sys_dpll_ldo_trim|=dpllinfo->data;
	ret=atbm_ahb_write_32(hw_priv,SMU_DPLL_PARAM_1_ADDR,sys_dpll_ldo_trim);
	
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant write sys_dpll_ldo_trim\n",__func__);
	 }

	/*sys_dpll_pc_vctrl*/
	ret=atbm_ahb_read_32(hw_priv,SMU_DPLL_PARAM_2_ADDR,&sys_dpll_pc_vctrl);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant read sys_dpll_ldo_trim\n",__func__);
	 }
	dpllinfo = &dpll_default.info[20];
	sys_dpll_pc_vctrl&=~0x70000;
	sys_dpll_pc_vctrl|=dpllinfo->data<<16;
	dpllinfo = &dpll_default.info[21];
	sys_dpll_pc_vctrl|=dpllinfo->data<<17;
	ret=atbm_ahb_write_32(hw_priv,SMU_DPLL_PARAM_2_ADDR,sys_dpll_pc_vctrl);
	
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant write sys_dpll_ldo_trim\n",__func__);
	 }
	/*sys_dpll_close_pll_loop*/
	ret=atbm_ahb_read_32(hw_priv,SMU_DPLL_CTRL_ADDR,&sys_dpll_close_pll_loop);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant read sys_dpll_close_pll_loop\n",__func__);
	 }
	dpllinfo = &dpll_default.info[9];
	sys_dpll_close_pll_loop&=~0x80;
	sys_dpll_close_pll_loop|=dpllinfo->data<<7;
	
	ret=atbm_ahb_write_32(hw_priv,SMU_DPLL_CTRL_ADDR,sys_dpll_close_pll_loop);
	
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant write sys_dpll_close_pll_loop\n",__func__);
	 }
	/*sys_dpll_en_sdm*/
	ret=atbm_ahb_read_32(hw_priv,SMU_DPLL_CTRL_ADDR,&sys_dpll_en_sdm);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant read sys_dpll_en_sdm\n",__func__);
	 }
	dpllinfo = &dpll_default.info[13];
	sys_dpll_en_sdm&=~0x8;
	sys_dpll_en_sdm|=dpllinfo->data<<3;
	ret=atbm_ahb_write_32(hw_priv,SMU_DPLL_CTRL_ADDR,sys_dpll_en_sdm);
	
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant write sys_dpll_close_pll_loop\n",__func__);
	 }

	/*sys_dpll_nint*/
	ret=atbm_ahb_read_32(hw_priv,SMU_DPLL_FRAC_ADDR,&sys_dpll_nint_nfrac);
	
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant read sys_dpll_nint\n",__func__);
	 }
	sys_dpll_nint_nfrac=0;
	dpllinfo = &dpll_default.info[17];
	sys_dpll_nint_nfrac|=dpllinfo->data;
	dpllinfo = &dpll_default.info[18];
	sys_dpll_nint_nfrac|=dpllinfo->data<<4;
	
	ret=atbm_ahb_write_32(hw_priv,SMU_DPLL_FRAC_ADDR,sys_dpll_nint_nfrac);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant write sys_dpll_nfrac\n",__func__);
	}
	dpllinfo = &dpll_default.info[26];
	sys_dpll_nint_nfrac|=dpllinfo->data<<8;
	dpllinfo = &dpll_default.info[27];
	sys_dpll_nint_nfrac|=dpllinfo->data<<16;
	
	dpllinfo = &dpll_default.info[28];
	sys_dpll_nint_nfrac|=dpllinfo->data<<24;
	
	ret=atbm_ahb_write_32(hw_priv,SMU_DPLL_FRAC_ADDR,sys_dpll_nint_nfrac);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant write sys_dpll_nfrac\n",__func__);
	}

	while(1){
		ret=atbm_ahb_read_32(hw_priv,SMU_DPLL_FRAC_ADDR,&sys_dpll_nint_nfrac);
		if (sys_dpll_nint_nfrac==0xd89d8949||sys_dpll_nint_nfrac==0x30)
		{
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"========dpllClock=%d\n",dpllClock);
			break;
		}
	}
}

void atbm_set_config_to_smu_apolloC(struct atbm_common *hw_priv,int dpllClock)
{
#if defined(TEST_DCXO_CONFIG) || defined(TEST_DPLL_CONFIG)
	u32 register_addr;
#ifdef TEST_DPLL_CONFIG
	int ret=0;
	u32 sys_dpll_nint_nfrac;
#endif
#endif
	/*The first step:dcxo changed value write to smu*/
#ifdef TEST_DCXO_CONFIG
	for (register_addr=SMU_DCXO_TRIM_ADDR;register_addr<=SMU_DCXO_CRTRL_ADDR;)
	{
		atbm_write_dcxo_value_to_smu(hw_priv,register_addr);	
		register_addr+=0x4;
	}
#endif
#ifdef TEST_DPLL_CONFIG
	for (register_addr=SMU_DPLL_PARAM_1_ADDR;register_addr<=SMU_DPLL_CTRL_ADDR;)
	{
		atbm_write_dpll_value_to_smu(hw_priv,register_addr);	
		register_addr+=0x4;
	}
	while(1){
		ret=atbm_ahb_read_32(hw_priv,SMU_DPLL_FRAC_ADDR,&sys_dpll_nint_nfrac);
		if (sys_dpll_nint_nfrac==0xd89d8949||sys_dpll_nint_nfrac==0x30)
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"===========pllClock=%d\n",dpllClock);
			break;
		}
#endif
}
void atbm_debug_bus(struct atbm_common *hw_priv)
{
    u32 uRegValue;
    atbm_ahb_write_32(hw_priv,0x1610009c,0xff);
    atbm_ahb_read_32(hw_priv,0x1610009c,&uRegValue);
    atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"1++++0x1610009c+++uRegValue=%x\n",uRegValue);
}
void atbm_register_init(struct atbm_common *hw_priv)
{
	u32 uRegValue;
#define RFIP_ADDR 0x0acc0000
		atbm_ahb_write_32(hw_priv,RFIP_ADDR+0x184,0x0);
		atbm_ahb_read_32(hw_priv,RFIP_ADDR+0x184,&uRegValue);
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"1++++184+++uRegValue=%x\n",uRegValue);

		atbm_ahb_write_32(hw_priv,0x1610000c,0x2);
		atbm_ahb_read_32(hw_priv,0x1610000c,&uRegValue);
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"1++++0x1610000c+++uRegValue=%x\n",uRegValue);
//#define TEST_UART_FUNC
#ifdef TEST_UART_FUNC
		atbm_ahb_read_32(hw_priv,0x161000b8,&uRegValue);
		uRegValue &= ~(BIT(16)|BIT(17)|BIT(18)|7);
		atbm_ahb_write_32(hw_priv,0x161000b8,uRegValue);
		atbm_ahb_read_32(hw_priv,0x161000b8,&uRegValue);
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"1++++0x161000b8+++uRegValue=%x\n",uRegValue);
#endif
#define debug_bus 0
#if debug_bus
		/***********************************************/
		atbm_ahb_write_32(hw_priv,0x1610009c,0x1);
		atbm_ahb_read_32(hw_priv,0x1610009c,&uRegValue);
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"1++++0x1610009c+++uRegValue=%x\n",uRegValue);
		/************************************************/
		//atbm_ahb_write_32(hw_priv,0xac50000,0xe0);
		//atbm_ahb_read_32(hw_priv,0xac50000,&uRegValue);
		//atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"1++++0xac50000+++uRegValue=%x\n",uRegValue);
#endif
		#ifdef CHIP_V1601
		atbm_ahb_write_32(hw_priv,RFIP_ADDR+0x178,0x1400061);//|(0x10<<11));

		atbm_ahb_read_32(hw_priv,RFIP_ADDR+0x178,&uRegValue);
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"++++178+++uRegValue=%x\n",uRegValue);

		atbm_ahb_read_32(hw_priv,RFIP_ADDR+0x17c,&uRegValue);
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"++++17c+++uRegValue=%x\n",uRegValue);
		#endif	


		//atbm_ahb_read_32(hw_priv,RFIP_ADDR+0x184,&uRegValue);

		//atbm_ahb_write_32(hw_priv,RFIP_ADDR+0x184,BIT(5)|uRegValue);//|(0x10<<11));

		//atbm_ahb_read_32(hw_priv,RFIP_ADDR+0x184,&uRegValue);
		//atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"++++184+++uRegValue=%x\n",uRegValue);

		atbm_ahb_write_32(hw_priv,0x18e00014,0x200);

		atbm_ahb_read_32(hw_priv,0x18e00014,&uRegValue);

		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"0x18e00014 read %x\n",uRegValue);

}
int atbm_config_dpll(struct atbm_common *hw_priv,char* value,int prjType,int dpll_clock)
{
	int ret;
	int init_reg;
	u8 Dpll_val_suc_fail;
	u8 Dpll_val_vld;
	u8 Dpll_val_retry;
	u8 Dpll_val_pup;
	u8 Dpll_val_pd;
	u8 Dpll_val_rstn;
	u8 Dpll_val_rst_sdm;
	u8 dpll_fn_rst_n_pin;
	u8 Dpll_val_afc_start;
	u8 Dpll_val_vld_done;
	u8 Dpll_init_reg_real;
	u8 Dpll_init_reg_sdio;
	u8 Dpll_en_160b;
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:Start atbm_config_dpll\n",__LINE__);

	atbm_register_init(hw_priv);
	//atbm_debug_bus(hw_priv);
	/*The First step ,wait for Dpll success or fail*/
	/*wait for success or fail*/
	while(1){
		ret=atbm_reg_write_8(hw_priv,0x18,0x41);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dpll reg error",__func__);
			goto out;
		}
		ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_suc_fail);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dpll reg error",__func__);
			goto out;
		}
		/*success or fail*/
		if ((Dpll_val_suc_fail&BIT(2))||(Dpll_val_suc_fail&BIT(1))){

			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:Start Dpll_val_suc_fail\n",Dpll_val_suc_fail);
			break;
		}
	}
	delay_sdio(1500*50);
/*init all register */
	for (init_reg=0x0;init_reg<0xc;init_reg++)
	{
		/*1.0 read real signal reg cmd*/
		ret=atbm_reg_write_8(hw_priv,0x18,0x40+init_reg);/* read 0-96bit*/
		if (ret<0)
		{
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read action init_reg cmd error\n",__func__);
			goto out;

		}
		/*2.0 read real signal reg value*/
		ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_init_reg_real);
		if (ret<0)
		{
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dpll_init_reg value error\n",__func__);
			goto out;

		}
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:atbm_config_dpll+++++++\n",__func__);

		/*3.0 read the sdio reg cmd*/
		ret=atbm_reg_write_8(hw_priv,0x18,0x50+init_reg);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:write action init_reg cmd error\n",__func__);
			goto out;
		}

		/*4.0 read real signal reg value*/
		ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_init_reg_sdio);
		if (ret<0)
		{
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dpll_init_reg value error\n",__func__);
			goto out;

		}
		/*5.0 write the sdio reg cmd*/
		ret=atbm_reg_write_8(hw_priv,0x18,0xc0+init_reg);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:write action init_reg cmd error\n",__func__);
			goto out;
		}
		Dpll_init_reg_sdio=Dpll_init_reg_real;
		/*6.0 write the real signal to sdio reg*/

		ret =atbm_reg_write_8(hw_priv,0x19,Dpll_init_reg_sdio);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_init_reg_sdio(0-7bit) error",__LINE__);
			goto out;
		}
		/*7.0 write finish cmd*/
  		ret =atbm_reg_write_8(hw_priv,0x18,0xf0+init_reg);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish dpll_nfrac(0-7bit) error",__LINE__);
			goto out;
		}
		delay_sdio(50);

	}
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dpll default value is start---------\n");
	/*start config dpll test value*/
	atbm_dpll_test_value(hw_priv,value,prjType,dpll_clock);

/*
Clear real signal value,set the register default value
dpll cfg vld is 1,
dpll retry is 0,
dpll ref pup is 0
dpll pd is 1
dpll rstn is 0
dpll rst sdm is 0
dpll fn rst n pin is 0
dpll afc start is 1
*/
dpll_again:
/*start set reg value---dpll cfg vld */
	ret=atbm_reg_write_8(hw_priv,0x18,0x5b);/*80-95bit*/
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_val_vld error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_vld);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read Dpll_val_vld error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_vld\n",Dpll_val_vld);
	ret=atbm_reg_write_8(hw_priv,0x18,0xcb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action Dpll_val_vld error",__LINE__);
		goto out;
	}
	Dpll_val_vld&=0xf7;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_vld);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_vld error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_vld\n",Dpll_val_vld);
	ret =atbm_reg_write_8(hw_priv,0x18,0xfb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_vld error",__LINE__);
		goto out;
	}
	/*start set reg value---dpll retry*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x5b);/*80-95bit*/
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_val_retry_default error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_retry);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read Dpll_val_retry error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_retry\n",Dpll_val_retry);
	ret=atbm_reg_write_8(hw_priv,0x18,0xcb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action Dpll_val_retry error",__LINE__);
		goto out;
	}
	Dpll_val_retry&=0xfd;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_retry);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:Dpll_val_retry error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_retry\n",Dpll_val_retry);
	ret =atbm_reg_write_8(hw_priv,0x18,0xfb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_retry_default error",__LINE__);
		goto out;
	}

	/*start set reg value---dpll ref pup*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x51);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll ref pup errror",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_pup);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read pll ref pup error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_pup\n",Dpll_val_pup);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc1);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action pll ref pup error",__LINE__);
		goto out;
	}
	Dpll_val_pup&=0xbf;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_pup);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_pup error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:-----write Dpll_val_pup\n",Dpll_val_pup);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf1);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_pup(b'0000bit) error",__LINE__);
		goto out;
	}

	/*start set reg value ---dpll pd*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x53);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll pd errror",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_pd);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read dpll pd error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_pd\n",Dpll_val_pd);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll pd errror",__LINE__);
		goto out;
	}
	Dpll_val_pd|=0x80;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_pd);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll pd error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:-----write Dpll_val_pd\n",Dpll_val_pd);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_pd(b'0001bit) error",__LINE__);
		goto out;
	}

	/* start set  reg value --dpll rstn*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x54);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll rstn errror",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_rstn);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read dpll rstn errror",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++read Dpll_val_rstn\n",Dpll_val_rstn);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll rstn errror",__LINE__);
		goto out;
	}
	Dpll_val_rstn&=0xfd;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_rstn);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll rstn errror",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_rstn\n",Dpll_val_rstn);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_rstn(b'0010bit) error",__LINE__);
		goto out;
	}
	/*start set reg value ---dpll_rst_sdm*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x54);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll_rst_sdm error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_rst_sdm);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read  dpll_rst_sdm error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++read Dpll_val_rst_sdm\n",Dpll_val_rst_sdm);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll_rst_sdm error",__LINE__);
		goto out;
	}
	Dpll_val_rst_sdm&=0xfe;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_rst_sdm);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll_rst_sdm error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---write Dpll_val_rst_sdm\n",Dpll_val_rst_sdm);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_rst_sdm(b'0010bit) error",__LINE__);
		goto out;
	}

	/*start set reg value ---dpll_fn_rst_n_pin*/

	ret=atbm_reg_write_8(hw_priv,0x18,0x53);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}

	ret =atbm_reg_read_8(hw_priv,0x19,&dpll_fn_rst_n_pin);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++read dpll_fn_rst_n_pin\n",dpll_fn_rst_n_pin);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}
	dpll_fn_rst_n_pin&=0xbf;
	ret =atbm_reg_write_8(hw_priv,0x19,dpll_fn_rst_n_pin);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---write dpll_fn_rst_n_pin\n",dpll_fn_rst_n_pin);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish dpll_fn_rst_n_pin(b'0001bit) error",__LINE__);
		goto out;
	}

	/*start set reg value---dpll_afc_start*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x52);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_val_afc_start error",__LINE__);
		goto out;
	}

	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_afc_start);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read Dpll_val_afc_start error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++read Dpll_val_afc_start\n",Dpll_val_afc_start);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc2);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action Dpll_val_afc_start error",__LINE__);
		goto out;
	}
	Dpll_val_afc_start|=0x02;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_afc_start);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_afc_start error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---write Dpll_val_afc_start\n",Dpll_val_afc_start);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf2);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_afc_start(b'0001bit) error",__LINE__);
		goto out;
	}
/* start set reg value-----dpll_cfg_done*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x5b);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_val_vld_done error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_vld_done);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read  Dpll_val_vld_done error",__LINE__);
		goto out;
	}
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_vld_done\n",Dpll_val_vld_done);
	ret=atbm_reg_write_8(hw_priv,0x18,0xcb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action Dpll_val_vld_done error",__LINE__);
		goto out;
	}
	Dpll_val_vld_done&=0xfb;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_vld_done);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_vld_done error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_vld_done\n",Dpll_val_vld_done);
	ret =atbm_reg_write_8(hw_priv,0x18,0xfb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_vld_done error",__LINE__);
		goto out;
	}
/* clear real signal value end */
/*The second step */
	ret=atbm_reg_write_8(hw_priv,0x18,0x5b);/*80-95bit*/
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_val_retry error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_retry);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read Dpll_val_retry error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_retry\n",Dpll_val_retry);
	ret=atbm_reg_write_8(hw_priv,0x18,0xcb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll cfg vld & set dpll retry error",__LINE__);
		goto out;
	}
	Dpll_val_retry|=0x02;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_retry);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_retry error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_retry\n",Dpll_val_retry);
	ret =atbm_reg_write_8(hw_priv,0x18,0xfb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_retry(b0110bit) error",__LINE__);
		goto out;
	}
	while(1){
		ret=atbm_reg_write_8(hw_priv,0x18,0x51);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll_work_s & dpll_work_fail error",__LINE__);
			goto out;
		}
		ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_suc_fail);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dpll reg error",__func__);
			goto out;
		}
		/*success or fail idel*/
		if (((Dpll_val_suc_fail&BIT(2))==0)&&((Dpll_val_suc_fail&BIT(1))==0)){

			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:Start Dpll_val_suc_fail\n",Dpll_val_suc_fail);
			break;
		}
	}
/* set register value for timming---dpll cfg vld & dpll retry*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x5b);/*80-95bit*/
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_val_retry error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_retry);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read Dpll_val_retry error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_retry\n",Dpll_val_retry);
	ret=atbm_reg_write_8(hw_priv,0x18,0xcb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll cfg vld & set dpll retry error",__LINE__);
		goto out;
	}
	Dpll_val_retry|=0x08;
	Dpll_val_retry&=0xfd;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_retry);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_retry error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_retry\n",Dpll_val_retry);
	ret =atbm_reg_write_8(hw_priv,0x18,0xfb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_retry(b0110bit) error",__LINE__);
		goto out;
	}
	/* T1 wait for 10us*/
	delay_sdio(200*50);

/* set register value for timming--- dpll ref pup*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x51);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll ref pup errror",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_pup);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read pll ref pup error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_pup\n",Dpll_val_pup);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc1);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll ref pup errror",__LINE__);
		goto out;
	}
	Dpll_val_pup|=0x40;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_pup);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write pll ref pup error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_pup\n",Dpll_val_pup);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf1);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_pup(b'0000bit) error",__LINE__);
		goto out;
	}
/*T 2 wait for 10us*/
	delay_sdio(200*50);

/* set register value for timming---dpll pd*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x53);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll pd errror",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_pd);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read dpll pd errror",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++read Dpll_val_pd\n",Dpll_val_pd);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll pd errror",__LINE__);
		goto out;
	}
	Dpll_val_pd&=0x7f;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_pd);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll pd errror",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---write Dpll_val_pd\n",Dpll_val_pd);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_pd(b'0001bit) error",__LINE__);
		goto out;
	}
/*T3 wait for 50us*/
	delay_sdio(200*200);
/*  set register value for timming---dpll rstn*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x54);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll rstn errror",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_rstn);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read dpll rstn errror",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++read Dpll_val_rstn\n",Dpll_val_rstn);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll rstn errror",__LINE__);
		goto out;
	}
	Dpll_val_rstn|=0x02;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_rstn);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll rstn errror",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_rstn\n",Dpll_val_rstn);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_rstn(b'0010bit) error",__LINE__);
		goto out;
	}

/*T4 wait for 10us */
	delay_sdio(200*50);
/* set register value for timming----dpll_rst_sdm*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x54);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll_rst_sdm error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_rst_sdm);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read  dpll_rst_sdm error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++read Dpll_val_rst_sdm\n",Dpll_val_rst_sdm);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll_rst_sdm error",__LINE__);
		goto out;
	}
	Dpll_val_rst_sdm|=0x01;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_rst_sdm);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll_rst_sdm error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---write Dpll_val_rst_sdm\n",Dpll_val_rst_sdm);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_rst_sdm(b'0010bit) error",__LINE__);
		goto out;
	}
/*T5 wait for 10us*/
/* set register value for timming----dpll_fn_rst_n_pin*/

	delay_sdio(200*50);
	ret=atbm_reg_write_8(hw_priv,0x18,0x53);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}

	ret =atbm_reg_read_8(hw_priv,0x19,&dpll_fn_rst_n_pin);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++read dpll_fn_rst_n_pin\n",dpll_fn_rst_n_pin);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}
	dpll_fn_rst_n_pin|=0x40;
	ret =atbm_reg_write_8(hw_priv,0x19,dpll_fn_rst_n_pin);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---write dpll_fn_rst_n_pin\n",dpll_fn_rst_n_pin);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish dpll_fn_rst_n_pin(b'0001bit) error",__LINE__);
		goto out;
	}
/*T6 wait for 10us*/
/* set register value for timming-----dpll_afc_start*/
	delay_sdio(200*80);
	ret=atbm_reg_write_8(hw_priv,0x18,0x52);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_val_afc_start error",__LINE__);
		goto out;
	}

	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_afc_start);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read Dpll_val_afc_start error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++read Dpll_val_afc_start\n",Dpll_val_afc_start);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc2);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action Dpll_val_afc_start error",__LINE__);
		goto out;
	}
	Dpll_val_afc_start&=0xfd;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_afc_start);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_afc_start error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---write Dpll_val_afc_start\n",Dpll_val_afc_start);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf2);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_afc_start(b'0001bit) error",__LINE__);
		goto out;
	}

/*T7 wait for 500us*/
/*dpll_lock*/
	delay_sdio(200*800);
/*start set reg value ---Dpll_en_160b*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x52);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_en_160b error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_en_160b);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read  Dpll_en_160b error",__LINE__);
		goto out;
	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xc2);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action Dpll_val_vld error",__LINE__);
		goto out;
	}
	Dpll_en_160b|=0x08;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_en_160b);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_en_160b error",__LINE__);
		goto out;
	}
	ret =atbm_reg_write_8(hw_priv,0x18,0xf2);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_en_160b error",__LINE__);
		goto out;
	}

/* set register value for timming------dpll_cfg_done*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x5b);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_val_vld_done error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_vld_done);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read  Dpll_val_vld_done error",__LINE__);
		goto out;
	}
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_vld_done\n",Dpll_val_vld_done);
	ret=atbm_reg_write_8(hw_priv,0x18,0xcb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action Dpll_val_vld_done error",__LINE__);
		goto out;
	}
	Dpll_val_vld_done|=0x04;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_vld_done);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_vld_done error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_vld_done\n",Dpll_val_vld_done);
	ret =atbm_reg_write_8(hw_priv,0x18,0xfb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_vld_done error",__LINE__);
		goto out;
	}
/*The third step,wait for success fail state*/

	while(1){
		ret=atbm_reg_write_8(hw_priv,0x18,0x51);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll_work_s & dpll_work_fail error",__LINE__);
			goto out;
		}
		ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_suc_fail);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read dpll_work_s & dpll_work_fail error",__LINE__);
			goto out;
		}

		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_suc_fail\n",Dpll_val_suc_fail);
		/*success or fail*/
		if ((Dpll_val_suc_fail&0x04)==4){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dpll calibration fail!!!\n");
			goto dpll_again;
		}
		if ((Dpll_val_suc_fail&0x02)==2){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"dpll calibration success!!!\n");
			break;
		}
	}
/*read defalut value dpll*/
#ifdef READ_DPLL_VALUE
	atbm_dpll_read_default_value(hw_priv,value);
#endif
	return 0;
out:
	return -1;
}


int atbm_system_done(struct atbm_common *hw_priv)
{
	/*The seventh step set wup -0*/
	int ret;
	u16 val_wup;
	u32 sys_shut_down;
	u8 Dpll_val_suc_fail;
	u8 Dpll_val_vld;
	u8 Dpll_en_160b;
	u8 Dpll_val_pd;
	u8 Dpll_val_pup;
	u8 Dpll_val_rstn;
	u8 Dpll_val_rst_sdm;
	u8 dpll_fn_rst_n_pin;
	u8 Dpll_val_afc_start;
	ret = atbm_reg_read_16(hw_priv, ATBM_HIFREG_CONTROL_REG_ID, &val_wup);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%d,read wake up ",__LINE__);
		goto out;
	}
	val_wup&=~ATBM_HIFREG_CONT_WUP_BIT;
	ret = atbm_reg_write_16(hw_priv, ATBM_HIFREG_CONTROL_REG_ID,val_wup);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%d,write wake up 0",__LINE__);
		goto out;
	}
	delay_sdio(80);
	/*config jtag mode*/
	ret=atbm_config_jtag_mode(hw_priv);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%d:*****atbm_config_jtag_mode error !!!",__LINE__);
	}
	delay_sdio(50);
	/*
	/////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////
	*/

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:start sys_shut_down\n",__LINE__);
	/*The eigth step set sys shut down*/

	ret=atbm_ahb_read_32(hw_priv,0x16101000,&sys_shut_down);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant read sys_shut_down\n",__func__);
		goto out;
	 }
	sys_shut_down|=(BIT(0)|BIT(2));
	ret=atbm_ahb_write_32(hw_priv,0x16101000,sys_shut_down);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant write sys_shut_down\n",__func__);
		goto out;
	}

	while(0){
		ret=atbm_ahb_read_32(hw_priv,0x16101000,&sys_shut_down);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant read sys_shut_down\n",__func__);
			goto out;
		}
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++write sys_shut_down\n",sys_shut_down);
		if((sys_shut_down&0x01)==0x01){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"sys_shut_down OK ++++++\n");
			break;
		}
	}
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---read sys_shut_down\n",sys_shut_down);

/*==============================================================*/
	while(1){
		ret=atbm_reg_write_8(hw_priv,0x18,0x41);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll_work_s & dpll_work_fail error",__LINE__);
			goto out;
		}
		ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_suc_fail);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:read Dpll reg error",__func__);
			goto out;
		}

		/*success or fail idel*/
		if (((Dpll_val_suc_fail&BIT(2))==0)&&((Dpll_val_suc_fail&BIT(1))==0)){

			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:Start Dpll_val_suc_fail\n",Dpll_val_suc_fail);
			break;
		}
	}
/*start set reg value ---Dpll_en_160b*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x52);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_en_160b error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_en_160b);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read  Dpll_en_160b error",__LINE__);
		goto out;
	}
	ret=atbm_reg_write_8(hw_priv,0x18,0xc2);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action Dpll_val_vld error",__LINE__);
		goto out;
	}
	Dpll_en_160b&=0xf7;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_en_160b);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_en_160b error",__LINE__);
		goto out;
	}
	ret =atbm_reg_write_8(hw_priv,0x18,0xf2);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_en_160b error",__LINE__);
		goto out;
	}

	/*start set reg value ---dpll pd*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x53);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll pd errror",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_pd);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read dpll pd error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_pd\n",Dpll_val_pd);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll pd errror",__LINE__);
		goto out;
	}
	Dpll_val_pd|=0x80;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_pd);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll pd error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:-----write Dpll_val_pd\n",Dpll_val_pd);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_pd(b'0001bit) error",__LINE__);
		goto out;
	}

	delay_sdio(300);

	/*start set reg value---dpll ref pup*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x51);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll ref pup errror",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_pup);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read pll ref pup error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_pup\n",Dpll_val_pup);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc1);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action pll ref pup error",__LINE__);
		goto out;
	}
	Dpll_val_pup&=0xbf;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_pup);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_pup error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:-----write Dpll_val_pup\n",Dpll_val_pup);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf1);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_pup(b'0000bit) error",__LINE__);
		goto out;
	}
	/* start set  reg value --dpll rstn*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x54);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll rstn errror",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_rstn);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read dpll rstn errror",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++read Dpll_val_rstn\n",Dpll_val_rstn);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll rstn errror",__LINE__);
		goto out;
	}
	Dpll_val_rstn&=0xfd;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_rstn);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll rstn errror",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_rstn\n",Dpll_val_rstn);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_rstn(b'0010bit) error",__LINE__);
		goto out;
	}
	/*start set reg value ---dpll_rst_sdm*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x54);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll_rst_sdm error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_rst_sdm);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read  dpll_rst_sdm error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++read Dpll_val_rst_sdm\n",Dpll_val_rst_sdm);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll_rst_sdm error",__LINE__);
		goto out;
	}
	Dpll_val_rst_sdm&=0xfe;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_rst_sdm);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll_rst_sdm error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---write Dpll_val_rst_sdm\n",Dpll_val_rst_sdm);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf4);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_rst_sdm(b'0010bit) error",__LINE__);
		goto out;
	}

	/*start set reg value ---dpll_fn_rst_n_pin*/

	ret=atbm_reg_write_8(hw_priv,0x18,0x53);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}

	ret =atbm_reg_read_8(hw_priv,0x19,&dpll_fn_rst_n_pin);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:+++read dpll_fn_rst_n_pin\n",dpll_fn_rst_n_pin);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}
	dpll_fn_rst_n_pin&=0xbf;
	ret =atbm_reg_write_8(hw_priv,0x19,dpll_fn_rst_n_pin);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write dpll_fn_rst_n_pin error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---write dpll_fn_rst_n_pin\n",dpll_fn_rst_n_pin);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf3);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish dpll_fn_rst_n_pin(b'0001bit) error",__LINE__);
		goto out;
	}

	/*start set reg value---dpll_afc_start*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x52);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_val_afc_start error",__LINE__);
		goto out;
	}

	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_afc_start);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read Dpll_val_afc_start error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++read Dpll_val_afc_start\n",Dpll_val_afc_start);
	ret=atbm_reg_write_8(hw_priv,0x18,0xc2);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action Dpll_val_afc_start error",__LINE__);
		goto out;
	}
	Dpll_val_afc_start|=0x02;

	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_afc_start);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_afc_start error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:---write Dpll_val_afc_start\n",Dpll_val_afc_start);
	ret =atbm_reg_write_8(hw_priv,0x18,0xf2);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_afc_start(b'0001bit) error",__LINE__);
		goto out;
	}
	/*dpll_cfg_vld----0*/
	ret=atbm_reg_write_8(hw_priv,0x18,0x5b);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action Dpll_val_vld error",__LINE__);
		goto out;
	}
	ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_vld);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read  Dpll_val_vld error",__LINE__);
		goto out;
	}
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:++++read Dpll_val_vld\n",Dpll_val_vld);
	ret=atbm_reg_write_8(hw_priv,0x18,0xcb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write action Dpll_val_vld error",__LINE__);
		goto out;
	}
	Dpll_val_vld&=0xf7;
	ret =atbm_reg_write_8(hw_priv,0x19,Dpll_val_vld);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write Dpll_val_vld error",__LINE__);
		goto out;
	}

	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%x:----write Dpll_val_vld\n",Dpll_val_vld);
	ret =atbm_reg_write_8(hw_priv,0x18,0xfb);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:write finish Dpll_val_vld error",__LINE__);
		goto out;
	}
#ifdef TEST_DCXO_CONFIG
	struct dcxo_reg_info *pinfo;
	/*wait for dcxo idel success bit is 2& fail bit is 3*/
	atbm_wait_dcxo_idel(hw_priv,2,3);

	/*set register value for timming---dcxo_dig_clk_en==0*/
	pinfo = &dcxo_default.info[DCXO_DIG_CLOCK_EN_POSITION];
	dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,pinfo->data);
	delay_sdio(500);

	/*set register value for timming---Dcxo_ldo_pup==0 */
	pinfo = &dcxo_default.info[DCXO_LDO_PUP_POSITION];
	dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,pinfo->data);

	/*set register value for timming---dcxo cfg vld==0 */
    pinfo = &dcxo_default.info[DCXO_CFG_VAL_POSITION];
    dcxo_signal_config(hw_priv,pinfo->name,pinfo->start_bit,pinfo->end_bit,pinfo->data);

#endif
	return 0;
out:
	return -1;

}
int atbm_wait_wlan_rdy(struct atbm_common *hw_priv)
{
	int ret;
	u16 val16=0;
	/*set wakeup */
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,":Start atbm_wait_wlan_rdy++++++++\n");
	while(0){
		ret = atbm_reg_read_16(hw_priv,
			ATBM_HIFREG_CONTROL_REG_ID, &val16);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: wait_for_wakeup: can't read " \
				"control register.\n", __func__);
		       goto out;
		}

		if (val16 & ATBM_HIFREG_CONT_RDY_BIT) {
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,
				"WLAN device is ready.\n");
			break;
		}
	}
	if ((val16 & ATBM_HIFREG_CONT_RDY_BIT) == 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: wait_for_wakeup: device is not responding.\n",
			__func__);
		ret = -ETIMEDOUT;
		goto out;
	}
	return 0;
out:
	return -1;

}
int atbm_config_jtag_mode(struct atbm_common *hw_priv)
{
	int ret;
	int smu_jtag_mode;
	atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%s:atbm_config_jtag_mode\n",__func__);
	ret=atbm_ahb_read_32(hw_priv,0x1610102c,&smu_jtag_mode);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant read smu_nfrac_val\n",__func__);
		goto out;
	 }
	smu_jtag_mode|=0x00000001;
	ret=atbm_ahb_write_32(hw_priv,0x1610102c,smu_jtag_mode);
	if (ret<0){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,"%s:cant write smu_jtag_mode\n",__func__);
		goto out;
	}
	return 0;
out:
	return -1;
}
