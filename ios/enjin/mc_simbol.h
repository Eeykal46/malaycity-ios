// mc_simbol.h - DIJANA AUTOMATIK oleh ios/alat/jana_simbol.py
// JANGAN EDIT TANGAN. Jana semula selepas libGTASA.so berubah.
//
// Tujuan: buat client SA-MP MUDAH ALIH. Dulu client guna alamat keras
// (g_libGTASA + 0x2BD618) yang sah untuk SATU binari sahaja. Sekarang
// ia guna (nama simbol, offset) yang boleh dicari melalui dlsym, jadi
// binari Android DAN iOS boleh guna kod yang sama.
//
// 166/199 alamat dipetakan. 33 tiada simbol -> perlu semak manual.

#ifndef MC_SIMBOL_H
#define MC_SIMBOL_H

#define MC_SIMBOL_JUMLAH 199
#define MC_SIMBOL_BERJAYA 166

typedef struct {
    unsigned int  alamat;   // g_libGTASA + alamat (Android)
    const char*   simbol;   // nama dieksport, NULL jika tiada
    unsigned int  offset;   // bait dari pangkal simbol
} McSimbol;

static const McSimbol MC_SIMBOL[] = {
    { 0x6D008, 0, 0 },   // TIADA SIMBOL
    { 0x1984A5, 0, 0 },   // TIADA SIMBOL
    { 0x1A3A69, 0, 0 },   // TIADA SIMBOL
    { 0x1AD9D8, 0, 0 },   // TIADA SIMBOL
    { 0x1AE8DE, 0, 0 },   // TIADA SIMBOL
    { 0x1AEC84, 0, 0 },   // TIADA SIMBOL
    { 0x1B2558, 0, 0 },   // TIADA SIMBOL
    { 0x1BC269, 0, 0 },   // TIADA SIMBOL
    { 0x1C2C90, 0, 0 },   // TIADA SIMBOL
    { 0x1D16EA, 0, 0 },   // TIADA SIMBOL
    { 0x1D193A, 0, 0 },   // TIADA SIMBOL
    { 0x1DB764, 0, 0 },   // TIADA SIMBOL
    { 0x1DB9B0, 0, 0 },   // TIADA SIMBOL
    { 0x1DBA64, 0, 0 },   // TIADA SIMBOL
    { 0x1DBABC, 0, 0 },   // TIADA SIMBOL
    { 0x1E3810, 0, 0 },   // TIADA SIMBOL
    { 0x1E3A28, 0, 0 },   // TIADA SIMBOL
    { 0x1E9BC8, 0, 0 },   // TIADA SIMBOL
    { 0x1E9C64, 0, 0 },   // TIADA SIMBOL
    { 0x1E9C80, 0, 0 },   // TIADA SIMBOL
    { 0x1EAC8C, 0, 0 },   // TIADA SIMBOL
    { 0x23FDE0, "_Z21_rwOpenGLRasterCreatePvS_i", 0xAC },
    { 0x266FC8, "_ZN11RenderQueueC1Ev", 0x34 },
    { 0x26B03C, 0, 0 },   // TIADA SIMBOL
    { 0x26B046, 0, 0 },   // TIADA SIMBOL
    { 0x2700AC, "_Z16RwFrameTranslateP7RwFramePK5RwV3d15RwOpCombineType", 0x4C },
    { 0x2700F2, "_Z12RwFrameScaleP7RwFramePK5RwV3d15RwOpCombineType", 0x6 },
    { 0x270118, "_Z12RwFrameScaleP7RwFramePK5RwV3d15RwOpCombineType", 0x2C },
    { 0x270164, "_Z12RwFrameScaleP7RwFramePK5RwV3d15RwOpCombineType", 0x78 },
    { 0x295448, "png_read_end", 0x510 },
    { 0x2AB5C6, "png_write_iTXt", 0xE2 },
    { 0x2B0D5C, 0, 0 },   // TIADA SIMBOL
    { 0x2B2068, "inflate_blocks", 0x32C },
    { 0x2BD618, "_Z20RpGeometryStreamReadP8RwStream", 0x120 },
    { 0x2C3868, "_Z27RpBuildMeshGenerateTriStripP11RpBuildMeshPv", 0x354 },
    { 0x2CB7C8, 0, 0 },   // TIADA SIMBOL
    { 0x2CC144, 0, 0 },   // TIADA SIMBOL
    { 0x2D292C, "INT123_reset_id3", 0xC },
    { 0x2FEE76, "alcCaptureOpenDevice", 0x1E6 },
    { 0x308952, "alGetListener3i", 0xCA },
    { 0x320844, "_Z19OS_PointerGetNumberv", 0x0 },
    { 0x320850, "_Z17OS_PointerGetTypei", 0x0 },
    { 0x326FEC, "_Z25LIB_PointerGetCoordinatesiPiS_Pf", 0x0 },
    { 0x327040, "_Z20LIB_PointerGetButtonii", 0x4 },
    { 0x32706C, "_Z19LIB_PointerGetWheeli", 0x0 },
    { 0x3270AC, "_Z24LIB_PointerDoubleClickedii", 0x0 },
    { 0x339134, "_ZN13CAEMP3Decoder16DecodeEntireFileEPhjPjS1_S1_S1_", 0x58 },
    { 0x339404, "_ZN13CAEMP3Decoder10InitialiseEv", 0x28 },
    { 0x33DE70, "_ZN14CAdjustableHUD6UpdateEv", 0x410 },
    { 0x341F84, "_Z23NewSCCloudSaveAvailablei", 0x48 },
    { 0x362E02, 0, 0 },   // TIADA SIMBOL
    { 0x36A690, "_Z14Menu_MapRenderv", 0xCD0 },
    { 0x385E38, "_ZN30CWidgetRegionSteeringSelectionD0Ev", 0x0 },
    { 0x38BF00, "_ZN25CCustomBuildingDNPipeline18CustomPipeRenderCBEP10RwResEntryPvhj", 0x208 },
    { 0x394A30, "_ZN10CStreaming12RequestModelEii", 0x50 },
    { 0x3CE29C, "_ZN10CGameLogic6UpdateEv", 0xC6C },
    { 0x3E33C8, "_ZN8CPedPath19AddBuildingBlockadeEP7CEntityPA40_12CPedPathNodeP7CVector", 0x268 },
    { 0x3F4138, "_ZN11CTheScripts15StartTestScriptEv", 0xBC },
    { 0x3F4E8C, "_ZN14CRunningScript23ProcessCommands100To199Ei", 0x0 },
    { 0x3F61B6, "_ZN14CRunningScript23ProcessCommands100To199Ei", 0x132A },
    { 0x40AC28, "_ZN14CRunningScript25ProcessCommands2500To2599Ei", 0xC80 },
    { 0x423418, "_ZN14CRunningScript25ProcessCommands1500To1599Ei", 0x1DA0 },
    { 0x432E3C, "_ZN14CTrafficLights18DisplayActualLightEP7CEntity", 0x210 },
    { 0x43AF28, "_ZN13FxInfoNoise_c8GetValueEffffhPv", 0x1C },
    { 0x43FB5E, "_ZN10FxSystem_c6UpdateEP8RwCameraf", 0x13E },
    { 0x43FB86, "_ZN10FxSystem_c6UpdateEP8RwCameraf", 0x166 },
    { 0x4404C0, "_ZN10FxSystem_c14GetBoundingBoxEP7FxBox_c", 0xA0 },
    { 0x440538, "_ZN10FxSystem_c14GetBoundingBoxEP7FxBox_c", 0x118 },
    { 0x442120, "_ZN22CEventEditableResponse23ComputeResponseTaskTypeEP9CPedGroup", 0x134 },
    { 0x44217C, "_ZN22CEventEditableResponse23ComputeResponseTaskTypeEP9CPedGroup", 0x190 },
    { 0x454EF0, "_ZN13CEventHandler21ComputeDamageResponseEP6CEventP5CTaskS3_S3_", 0x900 },
    { 0x4A52FC, "_ZN4CCam21Process_M16_1stPersonERK7CVectorfff", 0x1454 },
    { 0x4A55E2, "_ZN4CCam14Process_RocketERK7CVectorfffb", 0x15E },
    { 0x4A82D4, "_ZN4CCam17Process_1stPersonERK7CVectorfff", 0x1BC },
    { 0x4C36E2, "_ZN24CControllerConfigManager30InitDefaultControlConfigJoyPadEj", 0xB16 },
    { 0x4C5902, "_ZN24CControllerConfigManager31InitDefaultControlConfigurationEv", 0x1A12 },
    { 0x4C6CF4, "_ZN24CControllerConfigManager42AffectControllerStateOn_ButtonDown_DrivingEi15eControllerTypeR16CControllerState", 0x298 },
    { 0x4C7CDC, "_ZN24CControllerConfigManager28DeleteMatchingCommonControlsE18e_ControllerActioni15eControllerType", 0xAC },
    { 0x4D644C, "_ZN5CGame7ProcessEv", 0x178 },
    { 0x4D8700, "_Z11RenderSceneb", 0x104 },
    { 0x4DD5E8, "_ZN4CPad12GetHandBrakeEv", 0xB4 },
    { 0x4DD9E8, "_ZN4CPad9GetWeaponEP4CPedb", 0x18 },
    { 0x524E88, "_ZN6CRadar13DrawCoordBlipEihif", 0x84 },
    { 0x524F58, "_ZN6CRadar13DrawCoordBlipEihif", 0x154 },
    { 0x5258D8, "_ZN6CRadar14DrawEntityBlipEihif", 0x618 },
    { 0x525960, "_ZN6CRadar14DrawEntityBlipEihif", 0x6A0 },
    { 0x52737C, "_ZN6CRadar13Draw3dMarkersEv", 0xA0 },
    { 0x5273F4, "_ZN6CRadar13Draw3dMarkersEv", 0x118 },
    { 0x530C8C, "_ZN15InteriorGroup_c17GetRandomInteriorEv", 0xCC },
    { 0x5353B4, "_ZN10Interior_c19Office_FurnishEdgesEv", 0x2E4 },
    { 0x55BB85, "_ZN7CCamera4InitEv", 0x155 },
    { 0x55BD6C, "_ZN7CCamera4InitEv", 0x33C },
    { 0x55BDA8, "_ZN7CCamera4InitEv", 0x378 },
    { 0x584850, "_ZN32CTaskComplexMedicTreatInjuredPed10CreateTaskEv", 0x64 },
    { 0x584884, "_ZN32CTaskComplexMedicTreatInjuredPed10CreateTaskEv", 0x98 },
    { 0x591272, "_ZN22CTaskComplexSeekEntityI33CEntitySeekPosCalculatorVehicleIdE14ControlSubTaskEP4CPed", 0x2B6 },
    { 0x59128E, "_ZN22CTaskComplexSeekEntityI33CEntitySeekPosCalculatorVehicleIdE14ControlSubTaskEP4CPed", 0x2D2 },
    { 0x5C0BC4, "_ZN10CPlayerPedC1Eib", 0x18 },
    { 0x5C3258, "_ZN10CPlayerPed17ClearWeaponTargetEv", 0x30 },
    { 0x5C8838, "_ZN10CPlayerPed19ControlButtonSprintE11eSprintType", 0x180 },
    { 0x5C9014, 0, 0 },   // TIADA SIMBOL
    { 0x5C9120, 0, 0 },   // TIADA SIMBOL
    { 0x5D1020, "_ZN15CLoadedCarGroup13PickRandomCarEbb", 0xB4 },
    { 0x5D1F48, "_ZN10BoneNode_c5LimitEf", 0x1F4 },
    { 0x5D1F5C, "_ZN10BoneNode_c5LimitEf", 0x208 },
    { 0x5D245C, "_ZN17BoneNodeManager_c5ResetEv", 0x44 },
    { 0x5D2468, "_ZN17BoneNodeManager_c11GetBoneNodeEv", 0x4 },
    { 0x5D3E60, "_ZN16IKChainManager_c14IsFacingTargetEP4CPedi", 0x8 },
    { 0x5D40F4, "_ZN19CGenericGameStorage35DoAnytimeSavingStuffAfterSucessLoadEv", 0x28 },
    { 0x5D4184, "_ZN19CGenericGameStorage34DoGameSpecificStuffAfterSucessLoadEv", 0x60 },
    { 0x5D41C4, "_ZN19CGenericGameStorage34DoGameSpecificStuffAfterSucessLoadEv", 0xA0 },
    { 0x5D428C, "_ZN19CGenericGameStorage29DoGameSpecificStuffBeforeSaveEv", 0x54 },
    { 0x5DDD30, "_ZN17CTaskSimpleUseGun17RemoveStanceAnimsEP4CPedf", 0x160 },
    { 0x5DF790, "_ZN17CTaskSimpleUseGun11SetMoveAnimEP4CPed", 0x10C },
    { 0x5DF794, "_ZN17CTaskSimpleUseGun11SetMoveAnimEP4CPed", 0x110 },
    { 0x5E492E, "_ZN32CTaskComplexKillPedOnFootStealth14ControlSubTaskEP4CPed", 0x19E },
    { 0x5E49E0, "_ZN32CTaskComplexKillPedOnFootStealth14ControlSubTaskEP4CPed", 0x250 },
    { 0x61572C, "_ZN33CTaskComplexGoToBoatSteeringWheel14ControlSubTaskEP4CPed", 0x34 },
    { 0x617248, "_ZNK29CTaskSimpleSetPedAsAutoDriver11GetTaskTypeEv", 0x0 },
    { 0x617258, "_ZNK33CTaskComplexGoToBoatSteeringWheel5CloneEv", 0x0 },
    { 0x61725E, "_ZNK33CTaskComplexGoToBoatSteeringWheel5CloneEv", 0x6 },
    { 0x617290, "_ZNK33CTaskComplexGoToBoatSteeringWheel5CloneEv", 0x38 },
    { 0x619294, "_ZN13CCarEnterExit22IsPlayerToQuitCarEnterERK4CPedRK8CVehicleiP5CTask", 0x9C },
    { 0x6653F4, "_ZN30CTaskComplexInvestigateDeadPed13CreateSubTaskEiP4CPed", 0x64 },
    { 0x665800, "_ZN30CTaskComplexInvestigateDeadPed14ControlSubTaskEP4CPed", 0x148 },
    { 0x66D641, "_ZN5CText4LoadEh", 0x4D },
    { 0x66EAC4, "_ZN11CAutomobileC1Eihh", 0x5C4 },
    { 0x66EAE8, "_ZN11CAutomobileC1Eihh", 0x5E8 },
    { 0x66EB90, "_ZN11CAutomobileC1Eihh", 0x690 },
    { 0x66F304, "_ZN11CAutomobile20SetupSuspensionLinesEv", 0x4A8 },
    { 0x66F3D4, "_ZN11CAutomobile16HydraulicControlEv", 0x50 },
    { 0x66F5AC, "_ZN11CAutomobile16HydraulicControlEv", 0x228 },
    { 0x66F9E8, "_ZN11CAutomobile16HydraulicControlEv", 0x664 },
    { 0x66FBD0, "_ZN11CAutomobile16HydraulicControlEv", 0x84C },
    { 0x66FE58, "_ZN11CAutomobile16HydraulicControlEv", 0xAD4 },
    { 0x66FF0C, "_ZN11CAutomobile16HydraulicControlEv", 0xB88 },
    { 0x67056C, "_ZN11CAutomobile21UpdateMovingCollisionEf", 0x5E4 },
    { 0x67063C, "_ZN11CAutomobile21UpdateMovingCollisionEf", 0x6B4 },
    { 0x670A10, "_ZN11CAutomobile23AddMovingCollisionSpeedER7CVector", 0x21C },
    { 0x670E1C, "_ZNK11CAutomobile11IsDoorReadyE6eDoors", 0x30 },
    { 0x6710C4, "_ZN11CAutomobile28dmgDrawCarCollidingParticlesERK7CVectorf11eWeaponType", 0x1B0 },
    { 0x671458, "_ZN11CAutomobile26ProcessCarOnFireAndExplodeEh", 0x298 },
    { 0x6716D0, "_ZN11CAutomobile26ProcessCarOnFireAndExplodeEh", 0x510 },
    { 0x6717BC, "_ZN11CAutomobile26ProcessCarOnFireAndExplodeEh", 0x5FC },
    { 0x67193C, "_ZN11CAutomobile13VehicleDamageEftP7CEntityP7CVectorS3_11eWeaponType", 0xB4 },
    { 0x67196C, "_ZN11CAutomobile13VehicleDamageEftP7CEntityP7CVectorS3_11eWeaponType", 0xE4 },
    { 0x671984, "_ZN11CAutomobile13VehicleDamageEftP7CEntityP7CVectorS3_11eWeaponType", 0xFC },
    { 0x671BBC, "_ZN11CAutomobile13VehicleDamageEftP7CEntityP7CVectorS3_11eWeaponType", 0x334 },
    { 0x671F10, "_ZN11CAutomobile13VehicleDamageEftP7CEntityP7CVectorS3_11eWeaponType", 0x688 },
    { 0x67205C, "_ZN11CAutomobile13VehicleDamageEftP7CEntityP7CVectorS3_11eWeaponType", 0x7D4 },
    { 0x672440, "_ZN11CAutomobile13VehicleDamageEftP7CEntityP7CVectorS3_11eWeaponType", 0xBB8 },
    { 0x672644, "_ZN11CAutomobile13VehicleDamageEftP7CEntityP7CVectorS3_11eWeaponType", 0xDBC },
    { 0x672880, "_ZN11CAutomobile19TellHeliToGoToCoorsEfffff", 0x48 },
    { 0x672D14, "_ZN11CAutomobile20SpawnFlyingComponentEij", 0x1A0 },
    { 0x6730F0, "_ZN11CAutomobile20SpawnFlyingComponentEij", 0x57C },
    { 0x67324C, "_ZN11CAutomobile14SetPanelDamageE7ePanelsb", 0x8C },
    { 0x67332C, "_ZN11CAutomobile14SetPanelDamageE7ePanelsb", 0x16C },
    { 0x6733F0, "_ZN11CAutomobile13SetDoorDamageE6eDoorsb", 0x34 },
    { 0x673950, "_ZN11CAutomobile15SetRandomDamageEb", 0x294 },
    { 0x674280, "_ZN11CAutomobile15ProcessBuoyancyEv", 0x6D8 },
    { 0x674418, "_ZN11CAutomobile15ProcessBuoyancyEv", 0x870 },
    { 0x6749D0, "_ZN11CAutomobile14ProcessControlEv", 0x434 },
    { 0x6750D4, "_ZN11CAutomobile14ProcessControlEv", 0xB38 },
    { 0x675320, "_ZN11CAutomobile14ProcessControlEv", 0xD84 },
    { 0x675394, "_ZN11CAutomobile14ProcessControlEv", 0xDF8 },
    { 0x675490, "_ZN11CAutomobile14ProcessControlEv", 0xEF4 },
    { 0x67589C, "_ZN11CAutomobile14ProcessControlEv", 0x1300 },
    { 0x675914, "_ZN11CAutomobile14ProcessControlEv", 0x1378 },
    { 0x675ABC, "_ZN11CAutomobile14ProcessControlEv", 0x1520 },
    { 0x675C68, "_ZN11CAutomobile14ProcessControlEv", 0x16CC },
    { 0x675DE4, "_ZN11CAutomobile14ProcessControlEv", 0x1848 },
    { 0x675E6C, "_ZN11CAutomobile14ProcessControlEv", 0x18D0 },
    { 0x676034, "_ZN11CAutomobile14ProcessControlEv", 0x1A98 },
    { 0x677498, "_ZN11CAutomobile19ProcessCarWheelPairEiifP7CVectorS1_fffb", 0x238 },
    { 0x6778B0, "_ZN11CAutomobile19ProcessCarWheelPairEiifP7CVectorS1_fffb", 0x650 },
    { 0x677B6C, "_ZN11CAutomobile19ProcessCarWheelPairEiifP7CVectorS1_fffb", 0x90C },
    { 0x677CB4, "_ZN11CAutomobile16ProcessHarvesterEv", 0x5C },
    { 0x677EA0, "_ZN11CAutomobile16ProcessHarvesterEv", 0x248 },
    { 0x679B14, "_ZN11CAutomobile19ProcessSwingingDoorEi6eDoors", 0x1EC },
    { 0x6A84E0, "_ZN8CVehicle12RemoveDriverEb", 0xB4 },
    { 0x6A852C, "_ZN8CVehicle12RemoveDriverEb", 0x100 },
    { 0x6B8AF0, "_ZN11CWaterLevel20WaterLevelInitialiseEv", 0x468 },
    { 0x6BD174, "_ZN11CWaterLevel27CalculateWavesForCoordinateEiiffPfS0_S0_P7CVector", 0x26C },
    { 0x6E0098, "_ZN8CShadows19RenderStaticShadowsEb", 0x438 },
    { 0x6E00C0, "_ZN8CShadows19RenderStaticShadowsEb", 0x460 },
    { 0x6E00D9, "_ZN8CShadows19RenderStaticShadowsEb", 0x479 },
    { 0x70A38C, "_Z11DoGameStatev", 0x184 },
    { 0x70A43C, "_Z11DoGameStatev", 0x234 },
    { 0x70A458, "_Z11DoGameStatev", 0x250 },
    { 0x7BE2A8, 0, 0 },   // TIADA SIMBOL
    { 0x8ED870, "_ZN9CPlantMgr12m_LocTrisTabE", 0x1EB8 },
    { 0x951FA8, "_ZN10CStreaming16ms_aInfoForModelE", 0x5FE24 },
    { 0x952118, "_ZN10CStreaming16ms_aInfoForModelE", 0x5FF94 },
    { 0x96B500, "_ZN10CStreaming16ms_aInfoForModelE", 0x7937C },
    { 0x96B504, "_ZN10CStreaming16ms_aInfoForModelE", 0x79380 },
    { 0x96B514, "_ZN10CStreaming16ms_aInfoForModelE", 0x79390 },
    { 0xA26A90, 0, 0 },   // TIADA SIMBOL
    { 0xA7C264, 0, 0 },   // TIADA SIMBOL
    { 0xA987C8, 0, 0 },   // TIADA SIMBOL
};

#endif // MC_SIMBOL_H
