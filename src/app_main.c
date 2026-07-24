#include "app_main.h"
#include "sensors.h"

//uint8_t resp_time = false;

app_ctx_t g_appCtx;


//Must declare the application call back function which used by ZDO layer
const zdo_appIndCb_t appCbLst = {
    bdb_zdoStartDevCnf,		//start device cnf cb
    NULL,					//reset cnf cb
    NULL,					//device announce indication cb
    app_leaveIndHandler,	//leave ind cb
    app_leaveCnfHandler,	//leave cnf cb
    app_nwkUpdateIndicateHandler,//nwk update ind cb
    NULL,					//permit join ind cb
    NULL,					//nlme sync cnf cb
    NULL,					//tc join ind cb
    NULL,					//tc detects that the frame counter is near limit
    app_nwkStatusIndHandler,    //nwk status ind cb
};


/**
 *  @brief Definition for bdb commissioning setting
 */
bdb_commissionSetting_t g_bdbCommissionSetting = {
    .linkKey.tcLinkKey.keyType = SS_GLOBAL_LINK_KEY,
    .linkKey.tcLinkKey.key = (uint8_t *)tcLinkKeyCentralDefault,             //can use unique link key stored in NV

    .linkKey.distributeLinkKey.keyType = MASTER_KEY,
    .linkKey.distributeLinkKey.key = (uint8_t *)linkKeyDistributedMaster,    //use linkKeyDistributedCertification before testing

    .linkKey.touchLinkKey.keyType = MASTER_KEY,
    .linkKey.touchLinkKey.key = (uint8_t *)touchLinkKeyMaster,               //use touchLinkKeyCertification before testing

#if TOUCHLINK_SUPPORT
    .touchlinkEnable = 1,                                               /* enable touch-link */
#else
    .touchlinkEnable = 0,                                               /* disable touch-link */
#endif
    .touchlinkChannel = DEFAULT_CHANNEL,                                /* touch-link default operation channel for target */
    .touchlinkLqiThreshold = 0xA0,                                      /* threshold for touch-link scan req/resp command */
};

/*********************************************************************
*/
#if USE_NV_APP
// Test for compatible version of saved settings formats
void test_nv_version(void) {
	u32 ver = 0;
	if(nv_flashReadNew(1, NV_MODULE_APP, NV_ITEM_APP_DEV_VER, sizeof(ver), (u8 *)&ver) == NV_SUCC
		&& (ver & 0xFFFF) == (USE_NV_APP & 0xFFFF)
		&& ver >= USE_NV_APP_OK // compatible ?
		) {
	} else {
		sws_printf("test_nv_version: %8x:%8x\n", ver, USE_NV_APP);
		nv_resetAll();
		nv_resetModule(NV_MODULE_APP);
		// energy_remove(); ?
		ver = USE_NV_APP;
		nv_flashWriteNew(1, NV_MODULE_APP, NV_ITEM_APP_DEV_VER, sizeof(ver), (u8 *)&ver);
		// SYSTEM_RESET();
	}
}
#endif
/*********************************************************************
 * @fn      stack_init
 *
 * @brief   This function initialize the ZigBee stack and related profile. If HA/ZLL profile is
 *          enabled in this application, related cluster should be registered here.
 *
 * @param   None
 *
 * @return  None
 */
void stack_init(void)
{
	/* Initialize ZB stack */
	zb_init();

	/* Register stack CB */
    zb_zdoCbRegister((zdo_appIndCb_t *)&appCbLst);
}

/*********************************************************************
 * @fn      user_app_init
 *
 * @brief   This function initialize the application(Endpoint) information for this node.
 *
 * @param   None
 *
 * @return  None
 */
void user_app_init(void)
{
	af_nodeDescManuCodeUpdate(MANUFACTURER_CODE_TELINK);

    /* Initialize ZCL layer */
	/* Register Incoming ZCL Foundation command/response messages */
    zcl_init(app_zclProcessIncomingMsg);

	/* Register endPoint */
    af_endpointRegister(APP_ENDPOINT1, (af_simple_descriptor_t *)&app_ep1_simpleDesc, zcl_rx_handler, NULL);
    af_endpointRegister(APP_ENDPOINT2, (af_simple_descriptor_t *)&app_ep2_simpleDesc, zcl_rx_handler, NULL);

    /* Initialize or restore attributes, this must before 'zcl_register()' */
    zcl_appAttrsInit();
    zcl_reportingTabInit();

	/* Register ZCL specific cluster information */
    zcl_register(APP_ENDPOINT1, APP_CB_CLUSTER_NUM1, (zcl_specClusterInfo_t *)g_appClusterList1);
	zcl_register(APP_ENDPOINT2, APP_CB_CLUSTER_NUM2, (zcl_specClusterInfo_t *)g_appClusterList2);
	
#if ZCL_GP_SUPPORT
	/* Initialize GP */
	gp_init(APP_ENDPOINT1);
	gp_init(APP_ENDPOINT2);
#endif

#if ZCL_WWAH_SUPPORT
    /* Initialize WWAH server */
    wwah_init(WWAH_TYPE_SERVER, (af_simple_descriptor_t *)&app_simpleDesc);
#endif
}

void app_task(void) {
	buttonTask();
	if(dev_gpios.led2) {
		gpio_write(dev_gpios.led2,
				(dev_gpios.flg & GPIOS_FLG_LED2_POL)? cfg_on_off.onOff : !cfg_on_off.onOff);
	}

	if (BDB_STATE_GET() == BDB_STATE_IDLE)
		app_report_handler();
}

static void app_sysException(void) {

#if UART_PRINTF_MODE
    printf("app_sysException, line: %d, event: %d, reset\r\n", T_evtExcept[0], T_evtExcept[1]);
#endif

#if 1
    SYSTEM_RESET();
#else
    led_on(LED_STATUS);
    while(1);
#endif
}


#define REPORT_TIME_MIN_DEF			10		// 10 sec
#define REPORT_TIME_MAX_DEF			600		// 10 min
#define REPORT_TIME_STAT_DEF		3600	// 1 h
#define REPORT_TIME_MAX				65000

/*********************************************************************
 * @fn      user_init
 *
 * @brief   User level initialization code.
 *
 * @param   isRetention - if it is waking up with ram retention.
 *
 * @return  None
 */
//__attribute__((optimize("-Os")))
void user_init(bool isRetention)
{
#ifdef ZCL_METERING
	uint64_t reportableChange_u64;
#endif
	int32_t reportableChange_tmp;

#if USE_NV_APP
    if(!isRetention)
    	test_nv_version();
#endif

    /* Initialize GPIO led, key, relay, switch, ... */
    dev_gpios_init();


#if PA_ENABLE
    rf_paInit(PA_TX, PA_RX);
#endif
    /* Initialize Stack */
    stack_init();

    /* Initialize user application */
    user_app_init();

    /* Register except handler for test */
    sys_exceptHandlerRegister(app_sysException);

    /* User's Task */
#if ZBHCI_EN
    zbhciInit();
    ev_on_poll(EV_POLL_HCI, zbhciTask);
#endif
    ev_on_poll(EV_POLL_IDLE, app_task);

    /* Read the pre-install code from NV */
    if(bdb_preInstallCodeLoad(&g_appCtx.tcLinkKey.keyType, g_appCtx.tcLinkKey.key) == RET_OK){
        g_bdbCommissionSetting.linkKey.tcLinkKey.keyType = g_appCtx.tcLinkKey.keyType;
        g_bdbCommissionSetting.linkKey.tcLinkKey.key = g_appCtx.tcLinkKey.key;
    }

    /* Set default reporting configuration */
    reportableChange_tmp = 1;
#ifdef ZCL_ON_OFF
    /* OnOff */
    bdb_defaultReportingCfg(APP_ENDPOINT1, HA_PROFILE_ID,
			ZCL_CLUSTER_GEN_ON_OFF, ZCL_ATTRID_ONOFF,
            0, REPORT_TIME_MAX, (uint8_t *)&reportableChange_tmp);
#if USE_SWITCH
    bdb_defaultReportingCfg(APP_ENDPOINT1, HA_PROFILE_ID,
    		ZCL_CLUSTER_GEN_ON_OFF, ZCL_ATTRID_RELAY_STATE,
            0, REPORT_TIME_MAX, (uint8_t *)&reportableChange_tmp);
	bdb_defaultReportingCfg(APP_ENDPOINT2, HA_PROFILE_ID,
    		ZCL_CLUSTER_GEN_ON_OFF, ZCL_ATTRID_RELAY_STATE,
            0, REPORT_TIME_MAX, (uint8_t *)&reportableChange_tmp);
#endif
#endif
#ifdef ZCL_ON_OFF_SWITCH_CFG
    /* OnOffCfg */
    bdb_defaultReportingCfg(APP_ENDPOINT1, HA_PROFILE_ID,
    		ZCL_CLUSTER_GEN_ON_OFF_SWITCH_CONFIG, CUSTOM_ATTRID_DECOUPLED,
            0, REPORT_TIME_MAX, (uint8_t *)&reportableChange_tmp);
	bdb_defaultReportingCfg(APP_ENDPOINT2, HA_PROFILE_ID,
    		ZCL_CLUSTER_GEN_ON_OFF_SWITCH_CONFIG, CUSTOM_ATTRID_DECOUPLED,
            0, REPORT_TIME_MAX, (uint8_t *)&reportableChange_tmp);
#endif
#ifdef  ZCL_MULTISTATE_INPUT
    /* MultistateInput */
    bdb_defaultReportingCfg(APP_ENDPOINT1, HA_PROFILE_ID,
    		ZCL_CLUSTER_GEN_MULTISTATE_INPUT_BASIC, ZCL_MULTISTATE_INPUT_ATTRID_PRESENT_VALUE,
			0, REPORT_TIME_MAX, (uint8_t *)&reportableChange_tmp);
	bdb_defaultReportingCfg(APP_ENDPOINT2, HA_PROFILE_ID,
    		ZCL_CLUSTER_GEN_MULTISTATE_INPUT_BASIC, ZCL_MULTISTATE_INPUT_ATTRID_PRESENT_VALUE,
			0, REPORT_TIME_MAX, (uint8_t *)&reportableChange_tmp);
#endif

    /* Initialize BDB */
    bdb_init((af_simple_descriptor_t *)&app_ep1_simpleDesc, &g_bdbCommissionSetting, &g_zbBdbCb, 1);

    rf_setTxPower(ZB_TX_POWER_IDX_DEF);
#if USE_SWITCH
    switchFirstStart();
#endif
}

static int32_t net_steer_start_offCb(void *args) {

	g_appCtx.net_steer_start = false;

    light_blink_stop();

    return -1;
}

/*******************************************************************
 * @brief	factory reset start
 */
void factory_reset_start(void *args) {

    zb_factoryReset();

    g_appCtx.net_steer_start = true;
    g_appCtx.timerFactoryReset = TL_ZB_TIMER_SCHEDULE(net_steer_start_offCb, NULL, TIMEOUT_1MIN30SEC);
    light_blink_start(90, 250, 750);
}
