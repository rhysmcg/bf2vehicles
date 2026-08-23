rem ///////////////////////////////////////////////////////////////////////////
rem 
rem			Polar angle constraints
rem
rem ///////////////////////////////////////////////////////////////////////////

ragDoll.addAngularConstraint 31 6 7 160.0
ragDoll.addAngularConstraint 15 1 2 160.0

ragDoll.addAngularConstraint 1 2 4 110.0
ragDoll.addAngularConstraint 1 2 4 -150.0
ragDoll.addAngularConstraint 6 7 9 110.0
ragDoll.addAngularConstraint 6 7 9 -150.0

ragDoll.addAngularConstraint 1 6 7 95.0
ragDoll.addAngularConstraint 6 1 2 95.0

ragDoll.addAngularConstraint 15 16 19 95.0
ragDoll.addAngularConstraint 15 16 19 -150.0
ragDoll.addAngularConstraint 31 32 34 95.0
ragDoll.addAngularConstraint 31 32 34 -150.0

ragDoll.addAngularConstraint 6 31 32 60.0
ragDoll.addAngularConstraint 1 15 16 60.0

ragDoll.addAngularConstraint 16 15 31 110.0
ragDoll.addAngularConstraint 32 31 15 110.0

rem ///////////////////////////////////////////////////////////////////////////
rem 
rem			Dihedral angle constraints
rem
rem ///////////////////////////////////////////////////////////////////////////

ragDoll.addDihedralAngleConstraint 47 15 16 19 140.0
ragDoll.addDihedralAngleConstraint 47 31 32 34 140.0

ragDoll.addDihedralAngleConstraint 15 1 2 4 90.0
ragDoll.addDihedralAngleConstraint 31 6 7 9 90.0

rem ///////////////////////////////////////////////////////////////////////////
rem 
rem			particle-particle distance no less than constraints
rem
rem ///////////////////////////////////////////////////////////////////////////
ragdoll.addDistanceLessThanConstraint 19 1 0.175
ragdoll.addDistanceLessThanConstraint 34 6 0.175

rem ///////////////////////////////////////////////////////////////////////////
rem 
rem			particle-particle distance must equal constraints
rem
rem ///////////////////////////////////////////////////////////////////////////

ragDoll.addConstraint 1 2
ragDoll.addConstraint 47 1
ragDoll.addConstraint 47 6
ragDoll.addConstraint 6 31
ragDoll.addConstraint 7 9
ragDoll.addConstraint 6 7
ragDoll.addConstraint 2 4
ragDoll.addConstraint 32 34
ragDoll.addConstraint 31 32
ragDoll.addConstraint 16 19
ragDoll.addConstraint 15 16
ragDoll.addConstraint 1 31
ragDoll.addConstraint 6 15
ragDoll.addConstraint 1 15
ragDoll.addConstraint 15 31
ragDoll.addConstraint 47 31
ragDoll.addConstraint 47 15
ragDoll.addConstraint 6 1

rem ///////////////////////////////////////////////////////////////////////////
rem 
rem			Bone capsule collision constraints
rem
rem ///////////////////////////////////////////////////////////////////////////
ragDoll.addCapsuleCollision 1 2
ragDoll.addCapsuleCollision 2 4
ragDoll.addCapsuleCollision 6 7
ragDoll.addCapsuleCollision 7 9
ragDoll.addCapsuleCollision 6 31
ragDoll.addCapsuleCollision 1 15
ragDoll.addCapsuleCollision 31 32
ragDoll.addCapsuleCollision 32 34
ragDoll.addCapsuleCollision 15 16
ragDoll.addCapsuleCollision 16 19
ragDoll.addCapsuleCollision 15 31
ragDoll.addCapsuleCollision 1 6



