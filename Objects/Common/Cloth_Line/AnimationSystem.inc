
rem *** Animations ***
animationSystem.createAnimation Objects/Common/cloth_line/Animations/cloth_line_idle.baf

rem *** Bundles ***
animationSystem.createBundle cloth_idle
animationBundle.fadeInTime 0.1
animationBundle.fadeOutTime 0.2
animationBundle.addAnimation Objects/Common/cloth_line/Animations/cloth_line_idle.baf

rem *** Triggers ***
animationSystem.createTrigger Trigger root
animationTrigger.addBundle cloth_idle



