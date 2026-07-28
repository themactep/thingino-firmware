#include "apollo.h"
#include "hwio.h"
#include "fwio.h"
#include "bh.h"
#include "apollo_plat.h"
int atbm_config_dpll(struct atbm_common *hw_priv,char* value,int prjType,int dpllClock);
int atbm_config_dcxo(struct atbm_common *hw_priv,char *value,int prjType,int dcxoType,int dpllClock);
int atbm_wait_wlan_rdy(struct atbm_common *hw_priv);
int atbm_system_done(struct atbm_common *hw_priv);
int atbm_config_jtag_mode(struct atbm_common *hw_priv);
void atbm_set_config_to_smu_apolloC(struct atbm_common *hw_priv,int dpllClock);
void atbm_set_config_to_smu_apolloB(struct atbm_common *hw_priv,int dpllClock);
