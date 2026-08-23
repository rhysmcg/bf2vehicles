
rem *** Animations ***
animationSystem.createAnimation Objects/Common/Oil_Pump/Animations/oil_pump_pump.baf

rem *** Bundles ***
animationSystem.createBundle oil_pump_pump
animationBundle.fadeInTime 0.1
animationBundle.fadeOutTime 0.2
animationBundle.addAnimation Objects/Common/Oil_pump/Animations/oil_pump_pump.baf

rem *** Triggers ***
animationSystem.createTrigger Trigger root
animationTrigger.addBundle oil_pump_pump



