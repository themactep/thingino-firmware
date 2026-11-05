#ifndef __JZ_VPU_H__
#define __JZ_VPU_H__

/*
  _H264E_SliceInfo:
  H264 Encoder Slice Level Information
 */
typedef struct _H264E_SliceInfo {
  /*basic*/
  int     i_csp;
  uint8_t frame_type;
  uint8_t mb_width;
  uint8_t mb_height;
  uint8_t first_mby;
  uint8_t last_mby;  //for multi-slice

  /*vmau scaling list*/
  uint8_t scaling_list[4][16];

  /*loop filter*/
  uint8_t deblock;      // DBLK CTRL : enable deblock
  uint8_t rotate;       // DBLK CTRL : rotate
  int8_t alpha_c0_offset;   // cavlc use, can find in bs.h
  int8_t beta_offset;

  /*cabac*/   // current hw only use cabac, no cavlc
  uint8_t state[1024];
  unsigned int bs;          /* encode bitstream start address */
  uint8_t qp;

  /*frame buffer address: all of the buffers should be 256byte aligned!*/
  unsigned int fb[3][2];       /*{curr, ref, raw}{tile_y, tile_c}*/
  /* fb[0] : DBLK output Y/C address
   * fb[1] : MCE reference Y/C address
   * fb[2] : EFE input Y/C buffer address
   */
  unsigned int raw[3];         /*{rawy, rawu, rawv} or {rawy, rawc, N/C}*/
  int stride[2];          /*{stride_y, stride_c}, only used in raster raw*/

  /*descriptor address*/
  unsigned int * des_va, des_pa;

  /*TLB address*/
  unsigned int tlba;

}_H264E_SliceInfo;

#define REG_VPU_GLBC      0x00000
#define VPU_INTE_ACFGERR     (0x1<<20)
#define VPU_INTE_TLBERR      (0x1<<18)
#define VPU_INTE_BSERR       (0x1<<17)
#define VPU_INTE_ENDF        (0x1<<16)

#define REG_VPU_STAT      0x00034
#define VPU_STAT_ENDF    (0x1<<0)
#define VPU_STAT_BPF     (0x1<<1)
#define VPU_STAT_ACFGERR (0x1<<2)
#define VPU_STAT_TIMEOUT (0x1<<3)
#define VPU_STAT_JPGEND  (0x1<<4)
#define VPU_STAT_BSERR   (0x1<<7)
#define VPU_STAT_TLBERR  (0x1F<<10)
#define VPU_STAT_SLDERR  (0x1<<16)

#define REG_VPU_JPGC_STAT 0xE0008
#define JPGC_STAT_ENDF   (0x1<<31)

#define REG_VPU_SDE_STAT  0x90000
#define SDE_STAT_BSEND   (0x1<<1)
#define REG_VPU_ENC_LEN  (0x90038)

#define REG_VPU_DBLK_STAT 0x70070
#define DBLK_STAT_DOEND  (0x1<<0)

#define REG_VPU_AUX_STAT  0xA0010
#define AUX_STAT_MIRQP   (0x1<<0)

#define REG_VPU_LOCK		(0x9004c)
#define VPU_LOCK_END_FLAG	(1<<31)
#define VPU_LOCK_WAIT_OK	(1<<30)
#define VPU_LOCK_END		(1<<0)

#define CPM_VPU_SR(ID)		(31-3*(ID))
#define CPM_VPU_STP(ID)		(30-3*(ID))
#define CPM_VPU_ACK(ID)		(29-3*(ID))

#endif	/* __JZ_VPU_H__ */
