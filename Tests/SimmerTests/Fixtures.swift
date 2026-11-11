import Foundation

/// Real data captured on the reference Mac (M5 Pro, macOS 26.4, November 2026), trimmed.
enum Fixtures {
    /// `pmset -g log`: header, three sleeps (an AC "Software Sleep", a 1 s "Notification Wake Back to Sleep",
    /// and a long "Clamshell Sleep" with charger plug-in notification wakes), some assertion lines.
    /// Wake Requests and Assertions lines are cut to 200 characters; the timeline skips between the windows.
    static let pmsetLog = #"""
PM ASL data store: /var/log/powermanagement
2026-11-04 19:02:14 +0500 Assertions          	PID 279(mDNSResponder) Created MaintenanceWake "mDNSResponder:maintenance" 00:00:00  id:0x0xd0000819a [System: Pr
2026-11-04 19:02:14 +0500 Assertions          	PID 279(mDNSResponder) Released MaintenanceWake "mDNSResponder:maintenance" 00:00:00  id:0x0xd0000819a [System: P
2026-11-04 19:02:14 +0500 Assertions          	PID 112(powerd) Created InternalPreventSleep "PM configd - Wait for Device enumeration" 00:00:00  id:0x0xd0000819

Time stamp                Domain              	Message                                                                    	Duration  	Delay
==========                ======              	=======                                                                    	========  	=====
UUID: 052D06D0-0D20-4B52-9952-8E6FF9EFB9B5
2026-11-04 19:02:14 +0500 com.apple.sleepservices.sessionStarted	SleepService: window begins with cap time=180 secs
2026-11-10 05:03:08 +0500 Sleep               	Entering Sleep state due to 'Software Sleep pid=172':TCPKeepAlive=active Using AC (Charge:80%) 2 secs
2026-11-10 05:03:09 +0500 Wake Requests       	[process=dasd request=SleepService deltaSecs=1009 wakeAt=2026-11-10 05:19:58 info="com.apple.dasd:0:com.apple.MobileAccessoryUpdater.deviceIdleCheck"] [*
2026-11-10 05:03:10 +0500 DarkWake            	DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty centauri-alpha E_RX_IP_PACKET ARPT/ Using AC (Charge:80%) 45 secs
2026-11-10 05:03:11 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleSystemSleep "com.apple.audio.context25467.preventuseridlesleep" 00:17:55  id:0x0x100008d2b [System: DeclUser
2026-11-10 05:03:11 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context25485.preventuseridledisplaysleep" 00:17:55  id:0x0x500008d50 [System: D
2026-11-10 05:03:11 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleSystemSleep "com.apple.audio.context25521.preventuseridlesleep" 00:06:57  id:0x0x100008e1b [System: DeclUser
2026-11-10 05:03:11 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context25476.preventuseridledisplaysleep" 00:17:55  id:0x0x500008d3e [System: D
2026-11-10 05:03:55 +0500 Assertions          	Summary- [System: DeclUser IntPrevDisp kDisp] Using AC(Charge: 80)
2026-11-10 05:03:55 +0500 Sleep               	Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using AC (Charge:80%) 115 secs
2026-11-10 05:03:56 +0500 Wake Requests       	[*process=dasd request=SleepService deltaSecs=912 wakeAt=2026-11-10 05:19:08 info="com.apple.dasd:0:com.apple.MobileAccessoryUpdater.deviceIdleCheck"] [p
2026-11-10 05:05:50 +0500 DarkWake            	DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty centauri-alpha E_RX_IP_PACKET ARPT/ Using AC (Charge:80%) 45 secs
2026-11-10 05:06:25 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context25537.preventuseridledisplaysleep" 00:03:27  id:0x0x500008eb9 [System: D
2026-11-10 05:06:35 +0500 Sleep               	Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using AC (Charge:80%) 712 secs
2026-11-10 05:06:36 +0500 Wake Requests       	[*process=dasd request=SleepService deltaSecs=1001 wakeAt=2026-11-10 05:23:17 info="com.apple.dasd:0:com.apple.MobileAccessoryUpdater.deviceIdleCheck"] [
2026-11-10 05:18:27 +0500 DarkWake            	DarkWake from Deep Idle [CDNPB] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty centauri-alpha E_RX_IP_PACKET ARPT/ Using AC (Charge:80%) 45 secs
2026-11-10 05:18:28 +0500 Assertions          	Summary- [System: PrevIdle DeclUser PushSrvc BGTask SRPrevSleep IntPrevDisp kCPU kDisp] Using AC(Ch
2026-11-10 05:19:12 +0500 Sleep               	Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using AC (Charge:80%) 484 secs
2026-11-10 05:19:13 +0500 Wake Requests       	[process=dasd request=SleepService deltaSecs=1058 wakeAt=2026-11-10 05:36:51 info="com.apple.dasd:0:com.apple.MobileAccessoryUpdater.deviceIdleCheck"] [p
2026-11-10 13:24:08 +0500 DarkWake            	DarkWake from Deep Idle [CDNPB] : due to smc.sysState.Wake(0x70070000) USB2_wake SMC.OutboxNotEmpty nub-spmi-a0.0x0B/ Using AC (Charge:80%) 0 secs
2026-11-10 13:24:08 +0500 Assertions          	PID 112(powerd) CapExpired ApplePushServiceTask "Powerd - Wait for client pushService assertions" 00:00:00  id:0x0xa00009d87 [System: PrevIdle PrevSleep
2026-11-10 13:24:08 +0500 Wake                	DarkWake to FullWake from Deep Idle [CDNVA] : due to HID Activity Using AC (Charge:80%) 1077 secs
2026-11-10 22:18:43 +0500 Assertions          	PID 112(powerd) Summary InternalPreventSleep "com.apple.powermanagement.darkwakelinger" 00:00:00  id:0x0xd0000851e [System: PrevIdle DeclUser SRPrevSleep
2026-11-10 22:18:45 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context25798.preventuseridledisplaysleep" 02:03:12  id:0x0x50000a6a9 [System: P
2026-11-10 22:18:45 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleSystemSleep "com.apple.audio.context25800.preventuseridlesleep" 02:03:12  id:0x0x10000a6ac [System: PrevIdle
2026-11-10 22:18:45 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context25811.preventuseridledisplaysleep" 02:03:12  id:0x0x50000a6c3 [System: P
2026-11-10 22:18:45 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleSystemSleep "com.apple.audio.context25808.preventuseridlesleep" 02:03:12  id:0x0x10000a6bc [System: PrevIdle
2026-11-10 22:18:46 +0500 Sleep               	Entering DarkWake state due to 'Notification Wake Back to Sleep':TCPKeepAlive=active Using AC (Charge:86%)
2026-11-10 22:18:46 +0500 Assertions          	PID 112(powerd) Created InternalPreventSleep "com.apple.powermanagement.darkwakelinger" 00:00:00  id:0x0xd0000857b [System: PrevIdle PrevSleep DeclUser S
2026-11-10 22:18:55 +0500 Sleep               	Entering Sleep state due to 'Notification Wake Back to Sleep':TCPKeepAlive=active Using AC (Charge:86%) 1 secs
2026-11-10 22:18:55 +0500 Wake Requests       	[process=dasd request=SleepService deltaSecs=946 wakeAt=2026-11-10 22:34:41 info="com.apple.dasd:501:com.apple.duetexpertd.anchor-model-prediction-schedu
2026-11-10 22:18:56 +0500 Assertions          	PID 279(mDNSResponder) Released MaintenanceWake "mDNSResponder:maintenance" 00:00:00  id:0x0xd0000858d [System: PrevIdle DeclUser IntPrevDisp kDisp]
2026-11-10 22:18:56 +0500 Wake                	Wake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty centauri-alpha E_RX_IP_PACKET ARPT/HID Activity Using AC (Charge:86%)
2026-11-11 13:20:44 +0500 Sleep               	Entering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:86%) 2 secs
2026-11-11 13:20:44 +0500 Wake Requests       	[process=dasd request=SleepService deltaSecs=1050 wakeAt=2026-11-11 13:38:14 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [process=mDNS
2026-11-11 13:20:45 +0500 Assertions          	PID 279(mDNSResponder) Created MaintenanceWake "mDNSResponder:maintenance" 00:00:00  id:0x0xd00009cbb [System: No Assertions]
2026-11-11 13:20:46 +0500 DarkWake            	DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) USB-C_plug SMC.OutboxNotEmpty nub-spmi-a0.0x3F/ Using BATT (Charge:86%) 0 secs
2026-11-11 13:20:46 +0500 Wake                	DarkWake to FullWake from Deep Idle [CDNVAP] : due to Notification Using AC (Charge:86%) 3 secs
2026-11-11 13:20:46 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleSystemSleep "com.apple.audio.context26754.preventuseridlesleep" 07:59:19  id:0x0x1000094f5 [System: PrevIdle
2026-11-11 13:20:46 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context26745.preventuseridledisplaysleep" 07:59:19  id:0x0x5000094e3 [System: P
2026-11-11 13:20:46 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleSystemSleep "com.apple.audio.context26748.preventuseridlesleep" 07:59:19  id:0x0x1000094e8 [System: PrevIdle
2026-11-11 13:20:46 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context26767.preventuseridledisplaysleep" 07:59:19  id:0x0x500009510 [System: P
2026-11-11 13:20:49 +0500 Sleep               	Entering DarkWake state due to 'Notification Wake Back to Sleep':TCPKeepAlive=active Using AC (Charge:86%)
2026-11-11 13:21:21 +0500 Sleep               	Entering Sleep state due to 'Notification Wake Back to Sleep':TCPKeepAlive=active Using AC (Charge:86%) 2 secs
2026-11-11 13:21:22 +0500 Wake Requests       	[process=dasd request=SleepService deltaSecs=1077 wakeAt=2026-11-11 13:39:18 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [process=dasd
2026-11-11 13:21:23 +0500 DarkWake            	DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty centauri-alpha E_RX_IP_PACKET ARPT/ Using AC (Charge:86%) 45 secs
2026-11-11 13:21:23 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context26812.preventuseridledisplaysleep" 00:00:35  id:0x0x500009ccf [System: P
2026-11-11 13:21:23 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleSystemSleep "com.apple.audio.context26822.preventuseridlesleep" 00:00:35  id:0x0x100009ce2 [System: PrevIdle
2026-11-11 13:21:23 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context26836.preventuseridledisplaysleep" 00:00:35  id:0x0x500009cff [System: P
2026-11-11 13:21:23 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleSystemSleep "com.apple.audio.context26832.preventuseridlesleep" 00:00:35  id:0x0x100009cf6 [System: PrevIdle
2026-11-11 13:22:08 +0500 Sleep               	Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using AC (Charge:86%) 54 secs
2026-11-11 13:22:09 +0500 Wake Requests       	[process=dasd request=SleepService deltaSecs=1026 wakeAt=2026-11-11 13:39:14 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [*process=das
2026-11-11 13:23:02 +0500 Assertions          	PID 279(mDNSResponder) Released MaintenanceWake "mDNSResponder:maintenance" 00:00:00  id:0x0xd00009d19 [System: No Assertions]
2026-11-11 13:23:02 +0500 DarkWake            	DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty centauri-alpha E_RX_IP_PACKET ARPT/ Using AC (Charge:86%) 45 secs
2026-11-11 13:23:47 +0500 Sleep               	Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using AC (Charge:86%) 74 secs
2026-11-11 13:23:48 +0500 Wake Requests       	[*process=dasd request=SleepService deltaSecs=954 wakeAt=2026-11-11 13:39:41 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [process=dasd
2026-11-11 13:25:01 +0500 DarkWake            	DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty centauri-alpha E_RX_IP_PACKET ARPT/ Using AC (Charge:86%) 45 secs
2026-11-11 13:25:46 +0500 Sleep               	Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using AC (Charge:86%) 907 secs
2026-11-11 13:25:46 +0500 Wake Requests       	[*process=dasd request=SleepService deltaSecs=906 wakeAt=2026-11-11 13:40:52 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [process=dasd
2026-11-11 13:40:52 +0500 Assertions          	PID 279(mDNSResponder) Created MaintenanceWake "mDNSResponder:maintenance" 00:00:00  id:0x0xd00009d34 [System: PrevIdle SRPrevSleep kCPU]
2026-11-11 13:40:53 +0500 DarkWake            	DarkWake from Deep Idle [CDNPB] : due to NUB.SPMI0Sw3IRQ nub-spmi0.0x02 rtc/SleepService Using AC (Charge:86%) 45 secs
2026-11-11 13:41:38 +0500 Sleep               	Entering Sleep state due to 'Sleep Service Back to Sleep':TCPKeepAlive=active Using AC (Charge:86%) 169 secs
2026-11-11 13:41:38 +0500 Wake Requests       	[*process=dasd request=SleepService deltaSecs=901 wakeAt=2026-11-11 13:56:39 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [process=dasd
2026-11-11 13:44:27 +0500 DarkWake            	DarkWake from Deep Idle [CDNPB] : due to smc.sysState.Wake(0x70070000) USB-C_plug SMC.OutboxNotEmpty nub-spmi-a0.0x3F/ Using AC (Charge:86%) 41 secs
2026-11-11 13:44:28 +0500 Assertions          	Summary- [System: PushSrvc SRPrevSleep kCPU] Using Batt(Charge: 86)
2026-11-11 13:45:08 +0500 Sleep               	Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:86%) 98 secs
2026-11-11 13:45:08 +0500 Wake Requests       	[*process=dasd request=SleepService deltaSecs=1020 wakeAt=2026-11-11 14:02:08 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [process=mDN
2026-11-11 13:46:46 +0500 DarkWake            	DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) USB-C_plug SMC.OutboxNotEmpty nub-spmi-a0.0x3F/ Using BATT (Charge:86%) 0 secs
2026-11-11 13:46:46 +0500 Wake                	DarkWake to FullWake from Deep Idle [CDNVAP] : due to Notification Using AC (Charge:86%) 4 secs
2026-11-11 13:46:50 +0500 Assertions          	PID 80345(PowerChime) Released DisplayWake "com.apple.chimeOnAttach" 00:00:03  id:0x0xe00009d90 [System: PrevIdle PrevSleep SRPrevSleep kCPU]
2026-11-11 13:46:50 +0500 Sleep               	Entering DarkWake state due to 'Notification Wake Back to Sleep':TCPKeepAlive=active Using AC (Charge:86%)
2026-11-11 13:47:31 +0500 Sleep               	Entering Sleep state due to 'Notification Wake Back to Sleep':TCPKeepAlive=active Using AC (Charge:86%) 2 secs
2026-11-11 13:47:31 +0500 Wake Requests       	[process=dasd request=SleepService deltaSecs=985 wakeAt=2026-11-11 14:03:56 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [*process=dasd
2026-11-11 13:47:33 +0500 DarkWake            	DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty centauri-alpha E_RX_IP_PACKET ARPT/ Using AC (Charge:86%) 45 secs
2026-11-11 13:47:33 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleSystemSleep "com.apple.audio.context26855.preventuseridlesleep" 00:00:44  id:0x0x100009d99 [System: PushSrvc
2026-11-11 13:47:33 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context26866.preventuseridledisplaysleep" 00:00:44  id:0x0x500009db1 [System: P
2026-11-11 13:47:33 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleSystemSleep "com.apple.audio.context26867.preventuseridlesleep" 00:00:44  id:0x0x100009db2 [System: PushSrvc
2026-11-11 13:47:33 +0500 Assertions          	PID 183(coreaudiod) Released PreventUserIdleDisplaySleep "com.apple.audio.context26860.preventuseridledisplaysleep" 00:00:44  id:0x0x500009da4 [System: P
2026-11-11 13:48:18 +0500 Sleep               	Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using AC (Charge:86%) 1050 secs
2026-11-11 13:48:18 +0500 Wake Requests       	[*process=dasd request=SleepService deltaSecs=1049 wakeAt=2026-11-11 14:05:47 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [process=das
2026-11-11 17:34:34 +0500 Sleep               	Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:82%) 2 secs
2026-11-11 17:34:34 +0500 Wake Requests       	[*process=dasd request=SleepService deltaSecs=1077 wakeAt=2026-11-11 17:52:31 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [process=mDN
2026-11-11 17:34:36 +0500 DarkWake            	DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty centauri-alpha E_TKO_TCP_DATA ARPT/ Using BATT (Charge:82%) 28 secs
2026-11-11 17:35:04 +0500 Sleep               	Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:82%) 164 secs
2026-11-11 17:35:05 +0500 Wake Requests       	[*process=dasd request=SleepService deltaSecs=977 wakeAt=2026-11-11 17:51:21 info="com.apple.dasd:501:com.apple.filevault.healthanalytics"] [process=mDNS
2026-11-11 17:37:48 +0500 DarkWake            	DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) USB-C_plug SMC.OutboxNotEmpty nub-spmi-a0.0x3F/ Using BATT (Charge:82%) 1 secs
2026-11-11 17:37:48 +0500 Assertions          	Summary- [System: PrevIdle PushSrvc SRPrevSleep IPushSrvc kCPU] Using AC(Charge: 82)
2026-11-11 17:37:49 +0500 Wake                	DarkWake to FullWake from Deep Idle [CDNVAP] : due to Notification Using AC (Charge:82%) 3 secs
2026-11-11 17:37:52 +0500 Sleep               	Entering DarkWake state due to 'Notification Wake Back to Sleep':TCPKeepAlive=active Using AC (Charge:82%) 0 secs
2026-11-11 17:37:52 +0500 Assertions          	PID 170(WindowServer) Summary PreventSystemSleep "com.apple.WindowServer.DMGrace" 00:00:03  id:0x0x70000a129 [System: PrevIdle PrevSleep SRPrevSleep IPus
2026-11-11 17:37:52 +0500 Wake                	DarkWake to FullWake from Deep Idle [CDNVA] : due to HID Activity Using AC (Charge:82%)
"""#
}
