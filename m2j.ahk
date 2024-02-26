﻿;	;	;	;	;	;	;	;	;	;	;	;	;	;	;	;
;
#NoEnv  																; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input  														; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  											; Ensures a consistent starting directory.
#include CvJI/CvJoyInterface.ahk										; Credit to evilC.
; Settings
CoordMode,Mouse,Screen
SetMouseDelay,-1
; On exit
OnExit("exitFunc")
toggle:=1													; On/off parameter for the hotkey.	Toggle 0 means controller is on. The placement of this variable is disturbing.
; Icon
Menu,Tray,NoStandard
try
	Menu,Tray,Icon,ddores.dll,26
;Menu,Settings,openSettings
Menu,Tray,Add,About,aboutMenu
Menu,Tray,Add,Help,helpMenu
Menu,Tray,Add
Menu,Tray,Add,Select game, selectGameMenu
Menu,Tray,Add,Toggle knob size, knobMenu
Menu,Tray,Add,Settings,openSettings
Menu,Tray,Add
Menu,Tray,Add,Reload,reloadMenu
Menu,Tray,Add,Exit,exitFunc

; If no settings file, create, When changing this, remember to make corresponding changes after the setSettingsToDefault label (error handling) ; Currently at bottom of script
IfNotExist, settings.ini
{
	defaultSettings=
(
[General]
gameExe=notepad.exe
mouse2joystick=1
autoActivateGame=1
firstRun=1
[General>Setup]
r=160
k=0.35
fallBackPause=-1
nnp=1
[General>Hotkeys]
controllerSwitchKey=#s
exitKey=#q
moveAidKey=#d
[Mouse2Joystick>Axes]
angularDeadZone=22
invertedX=0
invertedY=0
[Mouse2Joystick>Keys]
joystickButtonKeyList=
autoHoldStickKey=#f
fixRadiusKey=#r
[Mouse2Keyboard>Keys]
upKey=w
downKey=s
leftKey=a
rightKey=d
LButtonReplacementKey=
RButtonReplacementKey=
[Visual aid]
kr=21
hideCursor=1
visualAidIsOn=1
autoPlaceVisualAid=1
nnVA=1
)
	FileAppend,%defaultSettings%,settings.ini
	If ErrorLevel
	{
		Msgbox,% 6+16,Error writing to file., There was a problem creating settings.ini
		, make sure you have permision to write to file at %A_ScriptDir%. If the problem persists`, try to run as administator or change the script directory. Press retry to try again`, continue to set all settings to default or cancel to exit application.
		IfMsgBox Retry
			reload
		else IfMsgBox Continue
			Goto, setSettingsToDefault	; Currently at bottom of script
		else 
			ExitApp
	}
}

; Read settings.

IniRead,allSections,settings.ini
if (!allSections || allSections="ERROR") ; Do not think this is ever set to ERROR.
{
	MsgBox, % 2+16, Error reading file, There was an error reading the settings.ini file`, press retry to try again`, continue to set all settings to default or cancel to exit application.
	IfMsgBox retry
		reload
	else IfMsgBox Ignore
		Goto, setSettingsToDefault	; Currently at bottom of script
	else 
		ExitApp
}
Loop,Parse,allSections,`n
{
	IniRead,pairs,settings.ini,%A_LoopField%
	Loop,Parse,pairs,`n
	{
		StringSplit,keyValue,A_LoopField,=
		%keyValue1%:=keyValue2
	}
}
readSettingsSkippedDueToError:	; This comes from setSettingsToDefault if there was an error.
IfNotExist images\*.png
{
	Msgbox,% 16, No images found., No image files were found, visual aid is disabled. Please place images in %A_ScriptDir%\images\
	visualAidIsOn:=0
	IniWrite,0,settings.ini,Visual aid,visualAidIsOn
}

pi:=atan(1)*4													; Approx pi.
angularDeadZone*=pi/180											; Convert to radians
angularDeadZone:=angularDeadZone>pi/4 ? pi/4:angularDeadZone	; Ensure correct range

; Constants and such. Some values are commented out because they have been stored in the settings.ini file instead, but are kept because they have comments.

;kr:=21											; Radius of the knob for the visual aid. Needs to match the actuall image, don't change if you don't change the image. (You can test smaller perhaps.) Verified, 10 works fine.
vW:=202											; Visual aid image width. Needs to match the actuall image, don't change if you don't change the image. Caveat: This implementation assumes vW=vH.
vH:=202											; Visual aid image height. Both the inner circle and the outer ring is assumed to have the same dimensions.


dr:=0											; Bounce back when hit outer circle edge, in pixels. (This might not work any more, it is off) Can be seen as a force feedback parameter, can be extended to depend on the over extension beyond the outer ring.
;r:=75											; This is acts as a sensitivity parameter, where values closer to zero corresponds higher sensitivity, should not be less than one.
;k:=0.50										; This parameter dictates the radius of the inner circle, inner=outer*k, k∈(0,1)

; Key set up
;controllerSwitchKey:="#s"						; Hotkey for toggling controller on/off
; Mouse button binds:							; Game does not receive mouse clicks when controller is on, bind to keyboard instead.
;LButtonReplacementKey:=""
;RButtonReplacementKey:=""

; Hotkey(s).
Hotkey,%controllerSwitchKey%,controllerSwitch, on
Hotkey,%exitKey%,exitFunc, on
Hotkey,%moveAidKey%,moveAid, on

;hideCursor:=1									; Set to 1 to hide the cursor when controller is on.
;visualAidIsOn:=1								; Set to 1 to show a visual aid for the controller.
;autoplaceVisualAid:=1							; Automatically places visual aid outside game screen.

freq:=25										; Controllers update frequency, in ms.
movingAid:=0									; Track when visual aid is in move mode.
actionTaken:=0									; For handling quick fall back to center. Needs to start at zero.
; New options
;joystickButtonKeyList:=""						; Comma delimited list of keynames for binding keys to joystick buttons.
;autoHoldStickKey:="o"							; Hotkey for toggling auto hold stick on/off.
;mouse2joystick:=1								; These two should not be 1 at the same time.

;mouse2joystick:=0								; Debugging this line should be removed

mouse2keyboard:=!mouse2joystick

if mouse2joystick
{
	Gosub, initCvJoyInterface
	Gosub, mouse2joystickHotkeys
}

;autoActivateGame:=0
;angularDeadZone:=pi/16							; Defines the area where only one axis is used. (half the area really) should not be pi/4 or greater.
;invertedX:=0									; Invert x-axis? 1:yes, 0:no
;invertedY:=1									; Invert y-axis? 1:yes, 0:no
pmX:=invertedX ? -1:1							; Sign for inverting axis
pmY:=invertedY ? -1:1
snapToFullTilt:=0.005							; This needs to be improved.
fr:=0											; Fixed radius.
;nnp:=4	 										; Non-linearity parameter for joystick output, 1 = linear, >1 higher sensitivity closer to full tilt, <1 higher sensitivity closer to deadzone. Recommended range, [0.1,6]. 
; New parameters
stickIsAutoHeld:=0								; Tracks the status of autohold stick. 0 means it is not being auto held.
;fallBackPause:=125								; Short mouse movement block after fall back. Set to zero to disable fallback

;gameExe:="notepad.exe"							 		; Game executable name, for activating the game and for sizing the gui overlay, when toggling on/off the controller.

keyNames:=[upKey, leftKey, downKey, rightKey]	; The order is important, corresponds to up/left/down/right on the "stick".
currentState:=[0,0,0,0]							; 0 means that the corresponding key in keyNames is up, 1 means down
segmentEndAngles:=Object()						; Each segment is defined by its angle, segment 1,...,12 -> end angle pi/6,pi/3,...,2*pi [rad]. (Unfortuantley its clockwise, with 0/2pi being at three o'clock)
Loop,12
	segmentEndAngles[A_Index]:=pi/6*A_Index


; Display on screen visual aid for joystick control
if visualAidIsOn
{
	; Visual aid gui, the center circle
	; Calculate the position and dimension of the inner circle.
	icX:=vW*(1-k)/2
	icY:=vH*(1-k)/2
	icW:=vW*k
	Gui, VA: new
	Gui, VA: +ToolWindow -Caption +AlwaysOnTop +HWNDva
	Gui, VA: add, Picture, BackgroundTrans X0 Y0, images\outerRing.png
	Gui, VA: add, Picture, BackgroundTrans X%icX% Y%icY% W%icW% H-1 hwndIC, images\innerCircle.png
	Gui, VA: Color, FFFFFF
	
	; Visual aid gui, the knob.
	kd:=kr*2														; Knob diameter.
	Gui, VAknob: new
	Gui, VAknob: +ToolWindow -Caption +AlwaysOnTop +HWNDknob
	Gui, VAknob: add, Picture,X0 Y0 W%kd% H-1, images\knob.png 
	Gui, VAknob: Color, FFFFFF
	
}

; Mouse blocker
; Transparent window that covers game screen to prevent game from capture the mouse.
Gui, Controller: New
Gui, Controller: +ToolWindow -Caption +AlwaysOnTop +HWNDstick
Gui, Controller: Color, FFFFFF

; Spam user with useless info, first time script runs.
if (firstRun)
{
	MsgBox,64,Welcome,Settings are accessed via Tray icon -> Settings.
	IniWrite,0,settings.ini,General,firstRun
}

return
; End autoexec.


moveAid:
	if (autoplaceVisualAid || !toggle)
		return
	movingAid:=!movingAid
	if movingAid
	{
		Gui, VA: show
		WinSet, Style, +0xC00000, ahk_id %va%
	}
	else
	{
		WinSet, Style, -0xC00000, ahk_id %va%
		Gui, VA: show, hide
	}
return

vaGuiClose:		
	WinSet, Style, -0xC00000, ahk_id %va%		; In case user closes va-gui when caption is on.
	Gui, VA: show, hide
	movingAid:=0
return

selectGameMenu:
	ToolTip, Point and click on the game you want to select`, right click to cancel.
	HotKey,RButton,selectGameMenuCancel,on
	KeyWait,LButton,D
	MouseGetPos,,,wum
	WinGet, new_gameExe,ProcessName,ahk_id %wum%
	if new_gameExe
	{
		Tooltip, You have selected %new_gameExe%.
		gameExe:=new_gameExe
		IniWrite,%gameExe%,settings.ini,General,gameExe
	}
	selectGameMenuCancel:
	HotKey,RButton,selectGameMenuCancel,Off
	SetTimer, tipOff,-3000
return

reloadMenu:
	reload
return

aboutMenu:
	Msgbox,32,About, Author: Helgef`nVersion 2.0 2016-08-17
return

helpMenu:
	Msgbox,% 4+ 32 , Open help in browser?, Visit autohotkey.com forum for help? Opens link in default browser.
	IfMsgBox Yes
		Run, https://autohotkey.com/boards/viewtopic.php?f=19&t=21489
return

knobMenu:
	if !toggle
		return
	kr:= kr=21 ? 10 : 21
	ToolTip, % "Knob size changed to: " . (kr=21 ? "big.":"small.")
	SetTimer,tipOff,-3000
	IniWrite,%kr%,settings.ini,Visual Aid,kr
	; Visual aid gui, the knob.
	kd:=kr*2														; Knob diameter.
	Gui, VAknob: destroy
	Gui, VAknob: new
	Gui, VAknob: +ToolWindow -Caption +AlwaysOnTop +HWNDknob
	Gui, VAknob: add, Picture,X0 Y0 W%kd% H-1, images\knob.png 
	Gui, VAknob: Color, FFFFFF
return

initCvJoyInterface:
	; Copied from joytest.ahk, from CvJoyInterface by evilC
	; Create an object from vJoy Interface Class.
	vJoyInterface := new CvJoyInterface()
	; Was vJoy installed and the DLL Loaded?
	if (!vJoyInterface.vJoyEnabled()){
		; Show log of what happened
		Msgbox,% 4+16,vJoy Error,% "vJoy needs to be installed. Would like to enable mouse to keyboard instead? Press no to exit application.`nLog:`n" . vJoyInterface.LoadLibraryLog ; Error handling changed.
		IfMsgBox Yes
		{
			IniWrite, 0,settings.ini,General,mouse2joystick
			reload
		}
		ExitApp
	}
	global vstick := vJoyInterface.Devices[1]
return

; Hotkey labels
; This switches on/off the controller.
controllerSwitch:
	if movingAid																				; Handle when controller is switched while visual aid is in move mode.
		return
	if toggle	; Starting controller
	{	
		if autoActivateGame
		{
			WinActivate,ahk_exe %gameExe%
			WinWaitActive, ahk_exe %gameExe%,,2
			if ErrorLevel	
			{
				MsgBox,16,Error, %gameExe% not activated.
				return
			}
			WinGetPos,gameX,gameY,gameW,gameH,ahk_exe %gameExe%									; Get game screen position and dimensions
		}
		else
		{
			gameX:=0
			gameY:=0
			gameW:=A_ScreenWidth
			gameH:=A_ScreenHeight
		}
		DllCall("User32.dll\ReleaseCapture")													; Release mouse capture from game.
		
		if visualAidIsOn																		; Show and place visual aid.
		{
			if autoplaceVisualAid
			{
				vY:=gameY+gameH/2-vH/2
				rightBoundExceeded:=gameX+gameW+vW+kr>A_ScreenWidth
				leftBoundExceeded:=gameX-vW-kr<0
				if rightBoundExceeded && leftBoundExceeded
					vX:=kr,vY:=kr
				else if rightBoundExceeded
					vX:=gameX-vW-kr
				else
					vX:=gameX+gameW+kr
				
				Gui, VA: Show, X%vX% Y%vY%  w%vW% h%vH%  NA,Visual aid for controller.			; Show visual aid outside bottom right corner of game screen
			}
			else
			{
					Gui, VA: Show, w%vW% h%vH% NA,Visual aid for controller.					; Show visual aid at last position
			}
			WinSet,TransColor, FFFFFF, ahk_id %va%
			if !autoplaceVisualAid
				WinGetPos,vX,vY,,,ahk_id %va%													; Get position and calculate it's center.
			vOX:=round(vX+vW/2)
			vOY:=round(vY+vH/2)
			
			Gui, VAknob: Show,% "NA X" vOX-kr " Y" vOY-kr " W41 H41",Controller knob			; Show visual aid, kr is the knob radius
			WinSet,TransColor, FFFFFF, ahk_id %knob%
		}

		; Controller origin is center of game screen or screen if autoActivateGame:=0. (This is not the visual aid)
		OX:=gameX+gameW/2				
		OY:=gameY+gameH/2

		MouseMove,OX,OY																			; Move mouse to controller origin
		
		; The mouse blocker
		Gui, Controller: Show,NA x%gameX% y%gameY% w%gameW% h%gameH%,Controller
		WinSet,Transparent,1,ahk_id %stick%														; Make transparent.
		DllCall("User32.dll\SetCapture", "Uint", stick)											; Let the controller capture the mouse.
		
		if hideCursor
			DllCall("User32.dll\ShowCursor", "Int", 0)
			
		if mouse2joystick
			SetTimer,mouseTojoystick,%freq%
		else if mouse2keyboard
			SetTimer,mouseTokeyboard,%freq%
	}
	else	; Shutting down controller
	{
		if mouse2joystick
		{
			SetTimer,mouseTojoystick,Off
			setStick(0,0) 															; Stick in equllibrium.
		}
		else if mouse2keyboard
		{		
			SetTimer,mouseTokeyboard,Off
			changeStateTo([0,0,0,0])	
		}			
		
		if hideCursor
			DllCall("User32.dll\ShowCursor", "Int", 1) 							; No need to show cursor if not hidden.
		if visualAidIsOn
		{
			WinHide, ahk_id %knob%
			WinHide, ahk_id %va%
		}
		DllCall("User32.dll\ReleaseCapture")									; This might be unnecessary
		stickIsAutoHeld:=0 														; Ensure stick is not being held
		WinHide, ahk_id %stick%
		
	}
	toggle:=!toggle
return

autoHoldStick:
	;
	;	Sub-routine for enabling user to lock joystick position and use mouse normally.
	;
	if !stickIsAutoHeld
	{
		; Here the stick is not being auto held and user wants to auto hold it.
		if hideCursor
			DllCall("User32.dll\ShowCursor", "Int", 1) 						; Show cursor
		
		
		
		WinHide, ahk_id %stick%
		DllCall("User32.dll\ReleaseCapture")	
		
		MouseGetPos,ahX,ahY													; Save mouse position
		MouseMove,OX,OY														; Move mouse
		if mouse2joystick
			SetTimer, mouseTojoystick, Off									; Shut down timer
		else if mouse2keyboard
			SetTimer, mouseTokeyboard, Off										
	}
	else
	{

		; Here the stick is being auto held and user wants to get back control.
		if hideCursor
			DllCall("User32.dll\ShowCursor", "Int", 0) 						; Hide cursor again		
		
		
		WinShow, ahk_id %stick%
		DllCall("User32.dll\SetCapture", "Uint", stick)						; Let the controller capture the mouse.
					
		MouseMove,ahX,ahY													; Move back mouse.
		if mouse2joystick
			SetTimer, mouseTojoystick, on									; Turn timer back on.
		else if mouse2keyboard
			SetTimer, mouseTokeyboard, on
	}
	stickIsAutoHeld:=!stickIsAutoHeld										; Toggle auto hold status
return

; Hotkeys mouse2joystick
#if (!toggle && mouse2joystick)
#if
mouse2joystickHotkeys:
	Hotkey, if, (!toggle && mouse2joystick)
	Loop, Parse, joystickButtonKeyList, `,
	{
		keyName:=A_LoopField
		if !keyName
			continue
		Hotkey,%keyName%, pressJoyButton, on 
		Hotkey,%keyName% Up, releaseJoyButton, on
	}
	if autoHoldStickKey
		HotKey, %autoHoldStickKey%, autoHoldStick, On
	if fixRadiusKey
		HotKey, %fixRadiusKey%, fixRadius, On
	Hotkey, if
return

fixRadius:
	if fr										; Toggle fixed/free.
	{
		fr:=0
		return
	}
	MouseGetPos,X,Y
	X-=OX										; Move to controller coord system.
	Y-=OY
	fr:=sqrt(X**2+Y**2) 						; Fix radius to current deflection.
return
; Labels for pressing and releasing joystick buttons.
pressJoyButton:
	keyName:=A_ThisHotkey
	joyButtonNumber:=""
	Loop, Parse, joystickButtonKeyList,`,
	{
		if (keyName=A_LoopField)
		{
			joyButtonNumber:=A_Index
			break
		}
	}
	if joyButtonNumber
		vstick.SetBtn(1,joyButtonNumber)
return

releaseJoyButton:
	keyName:=RegExReplace(A_ThisHotkey," Up$")
	joyButtonNumber:=""
	Loop, Parse, joystickButtonKeyList,`,
	{
		if (keyName=A_LoopField)
		{
			joyButtonNumber:=A_Index
			break
		}
	}
	if joyButtonNumber
		vstick.SetBtn(0,joyButtonNumber)
return


; Hotkeys mouse2keyboard
; Game does not receive mouse clicks when controller is on, bind to keyboard instead.
#if (!toggle && mouse2keyboard)


LButton::
	if LButtonReplacementKey
		Send,{%LButtonReplacementKey% down}
return

LButton Up::
if LButtonReplacementKey
		Send,{%LButtonReplacementKey% up}
return
RButton::
	if RButtonReplacementKey
		Send,{%RButtonReplacementKey% down}
return

RButton Up::
	if RButtonReplacementKey
		Send,{%RButtonReplacementKey% up}
return



MButton::
	if MButtonReplacementKey
		Send,{%MButtonReplacementKey% down}
return

MButton Up::
	if MButtonReplacementKey
		Send,{%MButtonReplacementKey% up}
return





+LButton::Send,{t down}
return

+LButton Up::Send,{t up}
return

Alt::Send,{v down}
return

Alt Up::Send,{v up}
return

WheelUp::Send,{Up}
return

1::Send,{Right}
return

Tab::Send,{Left}
return

Esc::Send,{Enter}
return


WheelDown::Send,{Down}
return
^LButton::Right
return
^RButton::Left
return




#if


; Labels

mouseTojoystick:	
	mouse2joystick(r,dr,OX,OY,vOX,vOY,kr)
return

mouseTokeyboard:	
	mouse2keyboard(r,dr,OX,OY,vOX,vOY,kr)
return

; Functions

mouse2joystick(r,dr,OX,OY,vOX,vOY,kr)
{
	; r is the radius of the outer circle.
	; dr is a bounce back parameter.
	; OX is the x coord of circle center.
	; OY is the y coord of circle center.
	; vOX is the x coord of the visual aid origin.
	; vOY is the y coord of the visual aid origin.
	; kr is the knob radius.
	; fr is the fixed radius
	global actionTaken, fallBackPause, visualAidIsOn, knob, vW, vH,k, nnp,nnVA,fr
	MouseGetPos,X,Y
	X-=OX										; Move to controller coord system.
	Y-=OY
	RR:=sqrt(X**2+Y**2)
	if fr										; If fixed radius.
	{
		X:=round(X*fr/RR)
		Y:=round(Y*fr/RR)
		RR:=sqrt(X**2+Y**2)
		MouseMove,X+OX,Y+OY 
	}
	else if (RR>r)								; Check if outside controller circle.
	{
		X:=round(X*(r-dr)/RR)
		Y:=round(Y*(r-dr)/RR)
		RR:=sqrt(X**2+Y**2)
		MouseMove,X+OX,Y+OY 					; Calculate point on controller circle, move back to screen/window coords, and move mouse.
	}
	
	; Calculate angle
	phi:=getAngle(X,Y)							
	
	if visualAidIsOn
	{
		; Map controller coords to visual aid coord system
		vr:=vW/2
		if (RR>k*r && nnp!=1 && nnVA)
		{
			A:=(vr-vr*k)*((RR-k*r)/(r-k*r))**nnp+vr*k	; Amplitude corrected to reflect non linearity parameter nnp.
			kX:=round(A*cos(phi))+vOX-kr
			kY:=round(A*sin(phi))+vOY-kr
		}
		else											; Inside the deadzone, the knob moves linearly.
		{
			kX:=round(vOX+(X/r)*vr-kr) 
			kY:=round(vOY+(Y/r)*vr-kr) 
		}

		SetWinDelay,-1
		WinMove,ahk_id %knob%,, kX,kY			; Move the knob.
	}
	
	
	if (RR>k*r) 								; Check if outside inner circle/deadzone.
	{
		; Call action function.
		
		action(phi,((RR-k*r)/(r-k*r))**nnp)		; nnp is a non-linearity parameter.	
		actionTaken:=1							; This will enable fall back to center when leaving outer ring.
	}
	else
	{
		setStick(0,0)							; Stick in equllibrium.
		if (fallBackPause!=-1 && actionTaken=1)					
		{
			MouseMove,OX,OY						; User has moved back to inner circle/deadzone, fall back to center.
			if visualAidIsOn
			{
				kX:=vOX-kr
				kY:=vOY-kr
				WinMove,ahk_id %knob%,, kX,kY	; Move the knob.
			}
			mouseBlock()						; Short mouse movmement block after fallback.
			actionTaken:=0						; This will enable leaving the inner circle/deadzone again.
		}
	}
}

action(phi,tilt)
{	
	; This is for mouse2joystick. mouse2keyboard calls actionm2k().
	; phi ∈ [0,2*pi] defines in which direction the stick is tilted.
	; tilt ∈ (0,1] defines the amount of tilt. 0 is no tilt, 1 is full tilt.
	; When this is called it is already established that the deadzone is left, or the inner radius.
	; pmX/pmY is used for inverting axis.
	; snapToFullTilt is used to ensure full tilt is possible, this needs to be improved, should be dependent on the sensitivity.
	global angularDeadZone,pmX,pmY,pi,snapToFullTilt

	; Adjust tilt
	tilt:=tilt>1 ? 1:tilt
	if (snapToFullTilt!=-1)
		tilt:=1-tilt<=snapToFullTilt ? 1:tilt
	
	; If in angular deadzone, only output to one axis is done, for easy "full tilt" in one direction without any small drift to other direction.
	; In angular deadzone, the output is "output"
	if (phi<3*pi/2+angularDeadZone && phi>3*pi/2-angularDeadZone)							; In angular deadzone for Y-axis forward tilt.
	{
		setStick(0,pmY*tilt)
		return
	}
	if (phi<pi+angularDeadZone && phi>pi-angularDeadZone)									; In angular deadzone for X-axis left    tilt.
	{
		setStick(-pmX*tilt,0)
		return
	}
	if (phi<pi/2+angularDeadZone && phi>pi/2-angularDeadZone)								; In angular deadzone for Y-axis down	 tilt.
	{
		setStick(0,-pmY*tilt)
		return
	}	
	if ((phi>2*pi-angularDeadZone && phi<2*pi) || (phi<angularDeadZone && phi>=0) )			; In angular deadzone for Y-axis right	 tilt.
	{
		setStick(pmX*tilt,0)
		return
	}
	
	; Not inside angular deadzone. Here leq and geq should be used. There are eight cases.
	
	; Two cases with forward+right
	; Tilt is forward and slightly right.
	lb:=3*pi/2+angularDeadZone						; lb is lower bound
	ub:=7*pi/4										; ub is upper bound
	if (phi>=lb && phi<=ub)							
	{
		x:=pmX*tilt*scale(phi,ub,lb)
		y:=pmY*tilt
		setStick(x,y)
		return
	}
	; Tilt is slightly forward and right.
	lb:=7*pi/4										; lb is lower bound
	ub:=2*pi-angularDeadZone						; ub is upper bound
	if (phi>=lb && phi<=ub)							
	{
		x:=pmX*tilt
		y:=pmY*tilt*scale(phi,lb,ub)
		setStick(x,y)
		return
	}
	
	; Two cases with right+downward
	; Tilt is right and slightly downward.
	lb:=angularDeadZone								; lb is lower bound
	ub:=pi/4										; ub is upper bound
	if (phi>=lb && phi<=ub)							
	{
		x:=pmX*tilt
		y:=-pmY*tilt*scale(phi,ub,lb)
		setStick(x,y)
		return
	}
	; Tilt is downward and slightly right.
	lb:=pi/4										; lb is lower bound
	ub:=pi/2-angularDeadZone						; ub is upper bound
	if (phi>=lb && phi<=ub)							
	{
		x:=pmX*tilt*scale(phi,lb,ub)
		y:=-pmY*tilt
		setStick(x,y)
		return
	}
	
	; Two cases with downward+left
	; Tilt is downward and slightly left.
	lb:=pi/2+angularDeadZone						; lb is lower bound
	ub:=3*pi/4										; ub is upper bound
	if (phi>=lb && phi<=ub)							
	{
		x:=-pmX*tilt*scale(phi,ub,lb)
		y:=-pmY*tilt
		setStick(x,y)
		return
	}
	; Tilt is left and slightly downward.
	lb:=3*pi/4										; lb is lower bound
	ub:=pi-angularDeadZone							; ub is upper bound
	if (phi>=lb && phi<=ub)							
	{
		x:=-pmX*tilt
		y:=-pmY*tilt*scale(phi,lb,ub)
		setStick(x,y)
		return
	}
	
	; Two cases with forward+left
	; Tilt is left and slightly forward.
	lb:=pi+angularDeadZone							; lb is lower bound
	ub:=5*pi/4										; ub is upper bound
	if (phi>=lb && phi<=ub)							
	{
		x:=-pmX*tilt
		y:=pmY*tilt*scale(phi,ub,lb)
		setStick(x,y)
		return
	}
	; Tilt is forward and slightly left.
	lb:=5*pi/4										; lb is lower bound
	ub:=3*pi/2-angularDeadZone						; ub is upper bound
	if (phi>=lb && phi<=ub)							
	{
		x:=-pmX*tilt*scale(phi,lb,ub)
		y:=pmY*tilt
		setStick(x,y)
		return
	}
	; This should not happen:
	setStick(0,0)
	MsgBox,16,Error, Error at phi=%phi%. Please report.
	return
}

scale(phi,lb,ub)
{
	; let phi->f(phi) then, f(ub)=0 and f(lb)=1
	return (phi-ub)/(lb-ub)
}

setStick(x,y)
{
	; Set joystick x-axis to 100*x % and y-axis to 100*y %
	; Input is x,y ∈ (-1,1) where 1 would mean full tilt in one direction, and -1 in the other, while zero would mean no tilt at all. Using this interval makes it easy to invert the axis
	; (mainly this was choosen beacause the author didn't know the correct interval to use in CvJoyInterface)
	; the input is not really compatible with the CvJoyInterface. Hence this transformation:
	x:=(x+1)*16384									; This maps x,y ∈ (-1,1) -> (0,32768)
	y:=(y+1)*16384
	; Use set by index.
	; x = 1, y = 2.
	; Alter x
	vstick.SetAxisByIndex(x,1)
	; Alter y
	vstick.SetAxisByIndex(y,2)
}


getQuadrant(phi)
{
	; Not used.
	global pi
	if (phi>0 && phi <= pi/2)
		return 1
	else if(phi>pi/2 && phi <= pi)
		return 2
	else if( phi>pi && phi <= 3*pi/2)
		return 3
	else if (phi>3*pi/2 && phi <= 2*pi)
		return 4
	return -1	; shouldn't happen
}


; Mouse to Keyboard

mouse2keyboard(r,dr,OX,OY,vOX,vOY,kr)
{
	; r is the radius of the outer circle.
	; dr is a bounce back parameter.
	; OX is the x coord of circle center.
	; OY is the y coord of circle center.
	; vOX is the x coord of the visual aid origin.
	; vOY is the y coord of the visual aid origin.
	; kr is the knob radius.
	global actionTaken, fallBackPause, visualAidIsOn, knob, vW, vH,k
	MouseGetPos,X,Y
	X-=OX										; Move to controller coord system.
	Y-=OY
	RR:=sqrt(X**2+Y**2)
	if (RR>r)									; Check if outside controller circle.
	{
		X:=round(X*(r-dr)/RR)
		Y:=round(Y*(r-dr)/RR)
		MouseMove,X+OX,Y+OY 					; Calculate point on controller circle, move back to screen/window coords, and move mouse.
	}
	if visualAidIsOn
	{
		; Map controller coords to visual aid coord system
		kX:=round(vOX+X/r*vW/2-kr)
		kY:=round(vOY+Y/r*vH/2-kr)
		SetWinDelay,-1
		WinMove,ahk_id %knob%,, kX,kY			; Move the knob.
	}
	if (RR>k*r) 								; Check if outside inner circle.
	{
		; Calculate segement
		phi:=getAngle(X,Y)
		seg:=getSegment(phi)
		; Call action function.
		actionm2k(seg)
		actionTaken:=1							; This will enable fall back to center when leaving outer circle.
	}
	else
	{
		changeStateTo([0,0,0,0])				; All keys up.
		if (fallBackPause!=-1 && actionTaken=1)					
		{
			MouseMove,OX,OY						; User has moved back to inner circle, fall back to center.
			if visualAidIsOn
			{
				kX:=vOX-kr
				kY:=vOY-kr
				WinMove,ahk_id %knob%,, kX,kY	; Move the knob.
				
			}
			mouseBlock()						; Short mouse movmement block after fallback.
			
			actionTaken:=0						; This will enable leaving the inner circle again.
		}
	}
}

actionm2k(seg)
{	
	; This is for mouse2keyboard. mouse2joystick calls action().
	; 1 is down, 0 is up newState:=[w a s d] 
	if (seg=1 || seg=12)			;	Keys down:
		changeStateTo([0,0,0,1])	;	d				
	else if (seg=2)
		changeStateTo([0,0,1,1])	;	s+d
	else if (seg=3 || seg= 4)
		changeStateTo([0,0,1,0])	;	s
	else if (seg=5)
		changeStateTo([0,1,1,0])	;	a+s
	else if (seg=6 || seg=7)
		changeStateTo([0,1,0,0])	;	a
	else if (seg=8)
		changeStateTo([1,1,0,0])	;	w+a
	else if (seg=9 || seg=10)
		changeStateTo([1,0,0,0])	;	w
	else if (seg=11)
		changeStateTo([1,0,0,1])	;	d+w
	else
		return -1 ; error
	return
}

changeStateTo(newState)
{	
	global keyNames, currentState
	Loop, 4
		if (newState[A_Index]!=currentState[A_Index] && keyNames[A_Index])				; added support for empty keys, ie, no press at all in some direction (&& keyNames[A_Index])
			Send,% "{" . keyNames[A_Index] . (newState[A_Index] ? " Down}" : " Up}")
	currentState:=newState
	return
}

getSegment(phi)
{
	global segmentEndAngles
	Loop 12
		if(phi<segmentEndAngles[A_Index])
			return A_Index
	return -1 ; error
}

; Shared functions, mouse2joystick mouse2keyboard
getAngle(x,y)
{
	global pi
	if (x=0)
		return 3*pi/2-(y>0)*pi
	phi:=atan(y/x)
	if (x<0 && y>0)
		return phi+pi
	if (x<0 && y<=0)
		return phi+pi
	if (x>0 && y<0)
		return phi+2*pi
	return phi
}
mouseBlock()
{
	global fallBackPause	
	BlockInput, MouseMove
	Sleep, %fallBackPause%
	BlockInput, MouseMoveOff
}

exitFunc()
{
	global
	if mouse2Joystick
	{
		setStick(0,0) 
		vstick.Relinquish()
	}
	else if mouse2keyboard
	{
		changeStateTo([0,0,0,0])
	}
	BlockInput, MouseMoveOff
	DllCall("User32.dll\ShowCursor", "Int", 1)
	ExitApp
}

; Misc labels and such
tipOff:
	Tooltip
return


;
; End Script.
; Start settings.
; This is auto generated.
;
openSettings:
if !toggle			; This is probably best.
	return
Gui, Main: Destroy ; Ops
hideShow=0 
win_name:="Mouse2Joystick/Keyboard Settings" 
submitOnlyOne:=0 
OX_client:=170
OY_client:=25
GoSub,readTreeString
Gui, Main: -Resize
GUI, Main: add, text, x10  , Options:
Gui, Main: Add, TreeView,  vMainTreeVar r16 w150 gTreeClick
Gui, Main: Add, button, x10 w100 gmainOk ,Ok
GUI, Main: Add, StatusBar
SB_SetParts(150,50)
GoSub,guiCode
GUI, Main:+HwndMAIN_HWND
Gui, Main: Show,, Mouse2Joystick/Keyboard Settings
Main_WinTitle=ahk_id %MAIN_HWND%
GuiControl, -Redraw, Main 
Gui, Main: default
TV_LoadTree(tree)
GuiControl, +Redraw, Main 
return	
TreeClick:
	lastSection:=section
	if A_GuiEvent = S
		selection:=A_EventInfo
	section:=selectionPath(selection)		
	SB_SetText("You are in: " . section,1)	
	TV_GetText(nodeName,selection)
	if (IsLabel(lastSection))
	{
		hideShow=0
		Gosub,%lastSection%	
	}
	section:=RegExReplace(section,"[ ]+","_")		
	if (IsLabel(section))
	{
		hideShow=1
		Gosub,%section%  	 
		hideShow=0			 
	}
return
mainOk:
	Gui, Main: Submit
	Gosub, SubmitAll
	; Get old hotkeys.
	; Disable old hotkeys
	Hotkey,%controllerSwitchKey%,controllerSwitch, off
	Hotkey,%exitKey%,exitFunc, off
	Hotkey,%moveAidKey%,moveAid, off

	; Joystick buttons
	Hotkey, if, (!toggle && mouse2joystick)
	Loop, Parse, joystickButtonKeyList, `,
	{
		keyName:=A_LoopField
		if !keyName
			continue
		Hotkey,%keyName%, pressJoyButton, off 
		Hotkey,%keyName% Up, releaseJoyButton, off
	}
	if autoHoldStickKey
		HotKey, %autoHoldStickKey%, autoHoldStick, off
	if fixRadiusKey
		HotKey, %fixRadiusKey%, fixRadius, off
	Hotkey, if

	; Read settings.
	
	IniRead,allSections,settings.ini
	
	Loop,Parse,allSections,`n
	{
		IniRead,pairs,settings.ini,%A_LoopField%
		Loop,Parse,pairs,`n
		{
			StringSplit,keyValue,A_LoopField,=
			%keyValue1%:=keyValue2
		}
	}
	IfNotExist images\*.png
	{
		Msgbox,% 16, No images found., No image files were found, visual aid is disabled. Please place images in %A_ScriptDir%\images\
		visualAidIsOn:=0
		IniWrite,0,settings.ini,Visual aid,visualAidIsOn
	}
	mouse2keyboard:=!mouse2joystick
	if mouse2joystick
	{
		Gosub, initCvJoyInterface
		Gosub, mouse2joystickHotkeys
	}
	pmX:=invertedX ? -1:1											; Sign for inverting axis
	pmY:=invertedY ? -1:1
	angularDeadZone*=pi/180											; Convert to radians
	angularDeadZone:=angularDeadZone>pi/4 ? pi/4:angularDeadZone	; Ensure correct range
	if visualAidIsOn
	{
		; Remake va.
		Gui, VA: destroy
		icX:=vW*(1-k)/2
		icY:=vH*(1-k)/2
		icW:=vW*k
		Gui, VA: new
		Gui, VA: +ToolWindow -Caption +AlwaysOnTop +HWNDva
		Gui, VA: add, Picture, BackgroundTrans X0 Y0, images\outerRing.png
		Gui, VA: add, Picture, BackgroundTrans X%icX% Y%icY% W%icW% H-1 hwndIC, images\innerCircle.png
		Gui, VA: Color, FFFFFF
	}
	; Enable new hotkeys
	Hotkey,%controllerSwitchKey%,controllerSwitch, on
	Hotkey,%exitKey%,exitFunc, on
	Hotkey,%moveAidKey%,moveAid, on
	
return
guiCode:
Iniread,editText,settings.ini,General,gameExe
editText:=RegExReplace(editText,"DELIM_\|_ITER","`n")
Gui, Main: add, Edit,Hidden   vedit1092695107 X185 Y115 r1 w150,%editText%
editText= 
Gui, Main: add, GroupBox,Hidden vtext23478877 X170 Y25 W520 H64,Output mode
Gui, Main: add, GroupBox,Hidden vtext1153671792 X170 Y95 W520 H53,Input desitnation
Gui, Main: add, GroupBox,Hidden vtext1396826083 X170 Y155 W520 H45,Activate Executable
Iniread,master_var,settings.ini,General,mouse2joystick
checkMe:= (master_var="1") ? 1:0
Gui, Main: Add, Radio, Hidden Section Group Checked%checkMe% vradio1244113855_1 X185 Y45, Mouse2Joystick (requires vJoy)
checkMe:= (master_var="0") ? 1:0
Gui, Main: Add, Radio, Hidden  Checked%checkMe% vradio1244113855_2,  Mouse2Keyboard
Iniread,master_var,settings.ini,General,autoActivateGame
checkMe:= (master_var="1") ? 1:0
Gui, Main: Add, Radio, Hidden Section Group Checked%checkMe% vradio1371042200_1 X185 Y175, Yes
checkMe:= (master_var="0") ? 1:0
Gui, Main: Add, Radio, Hidden ys Checked%checkMe% vradio1371042200_2,  No
Text=	
(
The name of the executable that will recieve the output.
)
Gui, Main: add, Text,Hidden vtext1439415306 X350 Y118,%Text%
Text= 
Text=	
(
Automatically activate executable  (if it is running)  when controller is switched on.
)
Gui, Main: add, Text,Hidden vtext1649409801 X285 Y175,%Text%
Text= 
Iniread,editText,settings.ini,General>Setup,r
editText:=RegExReplace(editText,"DELIM_\|_ITER","`n")
Gui, Main: add, Edit,Hidden Number   vedit968841594 X185 Y45 r1 w75,%editText%
editText= 
Iniread,editText,settings.ini,General>Setup,k
editText:=RegExReplace(editText,"DELIM_\|_ITER","`n")
Gui, Main: add, Edit,Hidden   vedit1484171716 X185 Y165 r1 w75,%editText%
editText= 
Iniread,editText,settings.ini,General>Setup,fallBackPause
editText:=RegExReplace(editText,"DELIM_\|_ITER","`n")
Gui, Main: add, Edit,Hidden   vedit1441011004 X185 Y225 r1 w75,%editText%
editText= 
Iniread,editText,settings.ini,General>Setup,nnp
editText:=RegExReplace(editText,"DELIM_\|_ITER","`n")
Gui, Main: add, Edit,Hidden   vedit1136845697 X185 Y105 r1 w75,%editText%
editText= 
Gui, Main: add, GroupBox,Hidden vtext1820027441 X170 Y25 W520 H53,Sensitivity
Gui, Main: add, GroupBox,Hidden vtext1761503059 X170 Y85 W520 H53,Non linear sensitivity
Gui, Main: add, GroupBox,Hidden vtext868645638 X170 Y145 W520 H53,Deadzone
Gui, Main: add, GroupBox,Hidden vtext303295627 X171 Y205 W520 H53,Fallback pause
Text=	
(
1 is linear, <1 lowers sensitivity away from center, >1 hightens sensitivity away center.
)
Gui, Main: add, Text,Hidden vtext1950133817 X270 Y109,%Text%
Text= 
Text=	
(
Range, (0,1). The center area (pink in the visual aid) where no output is sent.
)
Gui, Main: add, Text,Hidden vtext1365655690 X270 Y169,%Text%
Text= 
Text=	
(
ms. Snaps back to center when entering inner ring, and pauses. Set to -1 to disable.
)
Gui, Main: add, Text,Hidden vtext1314749378 X270 Y227,%Text%
Text= 
Text=	
(
Range, (0,Screen Height/2). Lower values corresponds to higher sensitivity.
)
Gui, Main: add, Text,Hidden vtext68851252 X270 Y48,%Text%
Text= 
Gui, Main: add, GroupBox,Hidden vtext495210823 X170 Y25 W520 H72,Quit application
Gui, Main: add, GroupBox,Hidden vtext199783574 X170 Y105 W520 H72,Toggle the controller on/off
Gui, Main: add, GroupBox,Hidden vtext1265532956 X170 Y185 W520 H72,Enable/disable movement of visual aid
Iniread,master_var,settings.ini,General>Hotkeys,controllerSwitchKey									
hotkey26759803_oldkey:=master_var															
Gui, Main: add, Hotkey, Hidden 0 vhotkey26759803 X185 Y125 W150,% RegExReplace(master_var,"#")
checkMe:=RegExMatch(master_var,"#") ? 1:0
Gui, Main: add, CheckBox, Hidden vhotkey26759803_addWinkey checked%checkMe%,Use modifer: Winkey
Iniread,master_var,settings.ini,General>Hotkeys,exitKey									
hotkey255211840_oldkey:=master_var															
Gui, Main: add, Hotkey, Hidden 0 vhotkey255211840 X185 Y45 W150,% RegExReplace(master_var,"#")
checkMe:=RegExMatch(master_var,"#") ? 1:0
Gui, Main: add, CheckBox, Hidden vhotkey255211840_addWinkey checked%checkMe%,Use modifer: Winkey
Iniread,master_var,settings.ini,General>Hotkeys,moveAidKey									
hotkey2127896190_oldkey:=master_var															
Gui, Main: add, Hotkey, Hidden 0 vhotkey2127896190 X185 Y205 W150,% RegExReplace(master_var,"#")
checkMe:=RegExMatch(master_var,"#") ? 1:0
Gui, Main: add, CheckBox, Hidden vhotkey2127896190_addWinkey checked%checkMe%,Use modifer: Winkey
Text=	
(
There is no input verification.
Follow instructions and don't try to break it.
)
Gui, Main: add, Text,Hidden vtext938990667 X170 Y25,%Text%
Text= 
Iniread,editText,settings.ini,Mouse2Joystick>Axes,angularDeadZone
editText:=RegExReplace(editText,"DELIM_\|_ITER","`n")
Gui, Main: add, Edit,Hidden Number  Limit2 vedit446078763 X185 Y155 r1 w75,%editText%
editText= 
Gui, Main: add, GroupBox,Hidden vtext1772933493 X170 Y35 W520 H45,Invert X-axis
Gui, Main: add, GroupBox,Hidden vtext11683084 X170 Y85 W520 H45,Invert Y-axis
Gui, Main: add, GroupBox,Hidden vtext1550313039 X170 Y135 W520 H53,Angular deadzone
Iniread,master_var,settings.ini,Mouse2Joystick>Axes,invertedX
checkMe:= (master_var="1") ? 1:0
Gui, Main: Add, Radio, Hidden Section Group Checked%checkMe% vradio1025876589_1 X185 Y55, Yes
checkMe:= (master_var="0") ? 1:0
Gui, Main: Add, Radio, Hidden ys Checked%checkMe% vradio1025876589_2,  No
Iniread,master_var,settings.ini,Mouse2Joystick>Axes,invertedY
checkMe:= (master_var="1") ? 1:0
Gui, Main: Add, Radio, Hidden Section Group Checked%checkMe% vradio122217493_1 X185 Y105, Yes
checkMe:= (master_var="0") ? 1:0
Gui, Main: Add, Radio, Hidden ys Checked%checkMe% vradio122217493_2,  No
Text=	
(
Range: [0,45]. Defines the area where only one axis is used.
)
Gui, Main: add, Text,Hidden vtext374447714 X275 Y159,%Text%
Text= 
Iniread,editText,settings.ini,Mouse2Joystick>Keys,joystickButtonKeyList
editText:=RegExReplace(editText,"DELIM_\|_ITER","`n")
Gui, Main: add, Edit,Hidden -Wrap   vedit1874406880 X185 Y50 r1 w475,%editText%
editText= 
Gui, Main: add, GroupBox,Hidden vtext906325482 X170 Y25 W520 H88,Keylist
Gui, Main: add, GroupBox,Hidden vtext1019731688 X170 Y125 W520 H92,Hotkeys
Iniread,master_var,settings.ini,Mouse2Joystick>Keys,autoHoldStickKey									
hotkey932981360_oldkey:=master_var															
Gui, Main: add, Hotkey, Hidden 0 vhotkey932981360 X185 Y165 W150,% RegExReplace(master_var,"#")
checkMe:=RegExMatch(master_var,"#") ? 1:0
Gui, Main: add, CheckBox, Hidden vhotkey932981360_addWinkey checked%checkMe%,Use modifer: Winkey

Iniread,master_var,settings.ini,Mouse2Joystick>Keys,fixRadiusKey																					
Gui, Main: add, Hotkey, Hidden 0 vhotkey93298136 X355 Y165 W150,% RegExReplace(master_var,"#")
checkMe:=RegExMatch(master_var,"#") ? 1:0
Gui, Main: add, CheckBox, Hidden vhotkey93298136_addWinkey checked%checkMe%,Use modifer: Winkey

Text=	
(
The key list is a comma delimited list of (ahk valid) keys, where each entry binds to a joystick button.
The first entry binds to the first joystick buttons, and so on. Blanks and modifers are allowed.
)
Gui, Main: add, Text,Hidden vtext789866609 X185 Y80,%Text%
Text= 
Text=	
(
Fix stick to current position:
)
Gui, Main: add, Text,Hidden vtext191419274 X185 Y145,%Text%
Text=	
(
Fix stick to current radius:
)
Gui, Main: add, Text,Hidden vtext19141927 X355 Y145,%Text%
Text= 
Text=	
(
There is no input verification.
Follow instructions and don't try to break it.
)
Gui, Main: add, Text,Hidden vtext1220495721 X170 Y25,%Text%
Text= 
Gui, Main: add, GroupBox,Hidden vtext388795812 X170 Y25 W510 H128,Keyboard output
Gui, Main: add, GroupBox,Hidden vtext483483623 X170 Y170 W510 H78,Mouse button key binds
Iniread,master_var,settings.ini,Mouse2Keyboard>Keys,upKey									
hotkey1964265821_oldkey:=master_var															
Gui, Main: add, Hotkey, Hidden Limit190 vhotkey1964265821 X290 Y40 W75,% RegExReplace(master_var,"#")
Iniread,master_var,settings.ini,Mouse2Keyboard>Keys,downKey									
hotkey599253628_oldkey:=master_var															
Gui, Main: add, Hotkey, Hidden Limit190 vhotkey599253628 X290 Y65 W75,% RegExReplace(master_var,"#")
Iniread,master_var,settings.ini,Mouse2Keyboard>Keys,leftKey									
hotkey1278963789_oldkey:=master_var															
Gui, Main: add, Hotkey, Hidden Limit190 vhotkey1278963789 X290 Y115 W75,% RegExReplace(master_var,"#")
Iniread,master_var,settings.ini,Mouse2Keyboard>Keys,rightKey									
hotkey2130103637_oldkey:=master_var															
Gui, Main: add, Hotkey, Hidden Limit190 vhotkey2130103637 X290 Y90 W75,% RegExReplace(master_var,"#")
Iniread,master_var,settings.ini,Mouse2Keyboard>Keys,LButtonReplacementKey									
hotkey225514912_oldkey:=master_var															
Gui, Main: add, Hotkey, Hidden Limit190 vhotkey225514912 X290 Y190 W75,% RegExReplace(master_var,"#")
Iniread,master_var,settings.ini,Mouse2Keyboard>Keys,RButtonReplacementKey									
hotkey83004604_oldkey:=master_var															
Gui, Main: add, Hotkey, Hidden Limit190 vhotkey83004604 X290 Y215 W75,% RegExReplace(master_var,"#")
Text=	
(
Up
)
Gui, Main: add, Text,Hidden vtext587730748 X185 Y45,%Text%
Text= 
Text=	
(
Down
)
Gui, Main: add, Text,Hidden vtext530033183 X185 Y70,%Text%
Text= 
Text=	
(
Left
)
Gui, Main: add, Text,Hidden vtext2143338622 X185 Y120,%Text%
Text= 
Text=	
(
Right
)
Gui, Main: add, Text,Hidden vtext172497039 X185 Y95,%Text%
Text= 
Text=	
(
Left mouse button
)
Gui, Main: add, Text,Hidden vtext996303547 X185 Y195,%Text%
Text= 
Text=	
(
Right mouse button
)
Gui, Main: add, Text,Hidden vtext863373581 X185 Y220,%Text%
Text= 
Iniread,master_var,settings.ini,Visual aid,hideCursor									
boxName=																				
(
Hide when controller is on.
)
checkMe:=(master_var="1" ) ? 1:(master_var="0" ? 0:-1)
Gui, Main: add, Checkbox, Hidden  Checked%checkMe% vcheckbox1135789786 X185 Y160,%boxName%
boxName= 
Gui, Main: add, GroupBox,Hidden vtext1829586573 X170 Y140 W520 H45,Cursor
Gui, Main: add, GroupBox,Hidden vtext833212790 X170 Y25 W520 H45,Enable visual aid
Gui, Main: add, GroupBox,Hidden vtext1505650515 X170 Y80 W520 H45,Enable automatic placement of visual aid
Gui, Main: add, GroupBox,Hidden vtext1612995781 X170 Y195 W520 H45,Enable nonlinear visual aid
Iniread,master_var,settings.ini,Visual aid,visualAidIsOn
checkMe:= (master_var="1") ? 1:0
Gui, Main: Add, Radio, Hidden Section Group Checked%checkMe% vradio2102688731_1 X185 Y45, Yes
checkMe:= (master_var="0") ? 1:0
Gui, Main: Add, Radio, Hidden ys Checked%checkMe% vradio2102688731_2,  No
Iniread,master_var,settings.ini,Visual aid,autoPlaceVisualAid
checkMe:= (master_var="1") ? 1:0
Gui, Main: Add, Radio, Hidden Section Group Checked%checkMe% vradio2030676791_1 X185 Y100, Yes
checkMe:= (master_var="0") ? 1:0
Gui, Main: Add, Radio, Hidden ys Checked%checkMe% vradio2030676791_2,  No

Iniread,master_var,settings.ini,Visual aid,nnVA
; Button number: 1.
checkMe:= (master_var="1") ? 1:0
Gui, Main: Add, Radio, Hidden Section Group Checked%checkMe% vradio487673732_1 X185 Y215, Yes
; Button number: 2.
checkMe:= (master_var="0") ? 1:0
Gui, Main: Add, Radio, Hidden ys Checked%checkMe% vradio487673732_2,  No

return 
SubmitAll:
submit_General:
	edit1092695107:=RegExReplace(edit1092695107,"`n","DELIM_|_ITER")				
	IniWrite,%edit1092695107%, settings.ini, General, gameExe
		if (radio1244113855_1=1)
			IniWrite,1, settings.ini, General, mouse2joystick
		if (radio1244113855_2=1)
			IniWrite,0, settings.ini, General, mouse2joystick
		if (radio1371042200_1=1)
			IniWrite,1, settings.ini, General, autoActivateGame
		if (radio1371042200_2=1)
			IniWrite,0, settings.ini, General, autoActivateGame
if submitOnlyOne
	return
submit_General>Setup:
	edit968841594:=RegExReplace(edit968841594,"`n","DELIM_|_ITER")				
	IniWrite,%edit968841594%, settings.ini, General>Setup, r
	edit1484171716:=RegExReplace(edit1484171716,"`n","DELIM_|_ITER")				
	IniWrite,%edit1484171716%, settings.ini, General>Setup, k
	edit1441011004:=RegExReplace(edit1441011004,"`n","DELIM_|_ITER")				
	IniWrite,%edit1441011004%, settings.ini, General>Setup, fallBackPause
	edit1136845697:=RegExReplace(edit1136845697,"`n","DELIM_|_ITER")				
	IniWrite,%edit1136845697%, settings.ini, General>Setup, nnp
if submitOnlyOne
	return
submit_General>Hotkeys:
	hotkey26759803:=hotkey26759803_addWinkey ? "#" . hotkey26759803:hotkey26759803
	IniWrite,%hotkey26759803%, settings.ini, General>Hotkeys, controllerSwitchKey
	hotkey255211840:=hotkey255211840_addWinkey ? "#" . hotkey255211840:hotkey255211840
	IniWrite,%hotkey255211840%, settings.ini, General>Hotkeys, exitKey
	hotkey2127896190:=hotkey2127896190_addWinkey ? "#" . hotkey2127896190:hotkey2127896190
	IniWrite,%hotkey2127896190%, settings.ini, General>Hotkeys, moveAidKey
if submitOnlyOne
	return
submit_Mouse2Joystick:
if submitOnlyOne
	return
submit_Mouse2Joystick>Axes:
	edit446078763:=RegExReplace(edit446078763,"`n","DELIM_|_ITER")				
	IniWrite,%edit446078763%, settings.ini, Mouse2Joystick>Axes, angularDeadZone
		if (radio1025876589_1=1)
			IniWrite,1, settings.ini, Mouse2Joystick>Axes, invertedX
		if (radio1025876589_2=1)
			IniWrite,0, settings.ini, Mouse2Joystick>Axes, invertedX
		if (radio122217493_1=1)
			IniWrite,1, settings.ini, Mouse2Joystick>Axes, invertedY
		if (radio122217493_2=1)
			IniWrite,0, settings.ini, Mouse2Joystick>Axes, invertedY
if submitOnlyOne
	return
submit_Mouse2Joystick>Keys:
	edit1874406880:=RegExReplace(edit1874406880,"`n","DELIM_|_ITER")				
	IniWrite,%edit1874406880%, settings.ini, Mouse2Joystick>Keys, joystickButtonKeyList
	hotkey932981360:=hotkey932981360_addWinkey ? "#" . hotkey932981360:hotkey932981360
	IniWrite,%hotkey932981360%, settings.ini, Mouse2Joystick>Keys, autoHoldStickKey
	
	hotkey93298136:=hotkey93298136_addWinkey ? "#" . hotkey93298136:hotkey93298136
	IniWrite,%hotkey93298136%, settings.ini, Mouse2Joystick>Keys,fixRadiusKey
	
if submitOnlyOne
	return
submit_Mouse2Keyboard:
if submitOnlyOne
	return
submit_Mouse2Keyboard>Keys:
	hotkey1964265821:=RegExReplace(hotkey1964265821,"[!^+]+")
	hotkey1964265821:=hotkey1964265821_addWinkey ? "#" . hotkey1964265821:hotkey1964265821
	IniWrite,%hotkey1964265821%, settings.ini, Mouse2Keyboard>Keys, upKey
	hotkey599253628:=RegExReplace(hotkey599253628,"[!^+]+")
	hotkey599253628:=hotkey599253628_addWinkey ? "#" . hotkey599253628:hotkey599253628
	IniWrite,%hotkey599253628%, settings.ini, Mouse2Keyboard>Keys, downKey
	hotkey1278963789:=RegExReplace(hotkey1278963789,"[!^+]+")
	hotkey1278963789:=hotkey1278963789_addWinkey ? "#" . hotkey1278963789:hotkey1278963789
	IniWrite,%hotkey1278963789%, settings.ini, Mouse2Keyboard>Keys, leftKey
	hotkey2130103637:=RegExReplace(hotkey2130103637,"[!^+]+")
	hotkey2130103637:=hotkey2130103637_addWinkey ? "#" . hotkey2130103637:hotkey2130103637
	IniWrite,%hotkey2130103637%, settings.ini, Mouse2Keyboard>Keys, rightKey
	hotkey225514912:=RegExReplace(hotkey225514912,"[!^+]+")
	hotkey225514912:=hotkey225514912_addWinkey ? "#" . hotkey225514912:hotkey225514912
	IniWrite,%hotkey225514912%, settings.ini, Mouse2Keyboard>Keys, LButtonReplacementKey
	hotkey83004604:=RegExReplace(hotkey83004604,"[!^+]+")
	hotkey83004604:=hotkey83004604_addWinkey ? "#" . hotkey83004604:hotkey83004604
	IniWrite,%hotkey83004604%, settings.ini, Mouse2Keyboard>Keys, RButtonReplacementKey
if submitOnlyOne
	return
submit_Visual_aid:
			writeVal:=(checkbox1135789786=1) ? "1" : "0"
			IniWrite,%writeVal%, settings.ini, Visual aid, hideCursor
		if (radio2102688731_1=1)
			IniWrite,1, settings.ini, Visual aid, visualAidIsOn
		if (radio2102688731_2=1)
			IniWrite,0, settings.ini, Visual aid, visualAidIsOn
		if (radio2030676791_1=1)
			IniWrite,1, settings.ini, Visual aid, autoPlaceVisualAid
		if (radio2030676791_2=1)
			IniWrite,0, settings.ini, Visual aid, autoPlaceVisualAid
		
		if (radio487673732_1=1)
			IniWrite,1, settings.ini, Visual aid, nnVA
		if (radio487673732_2=1)
			IniWrite,0, settings.ini, Visual aid, nnVA
if submitOnlyOne
	return
return
General:
GuiControl, Main: Show%hideShow%, edit1092695107
GuiControl, Main: Enable%hideShow%, edit1092695107
GuiControl, Main: Show%hideShow%, text23478877
GuiControl, Main: Show%hideShow%, text1153671792
GuiControl, Main: Show%hideShow%, text1396826083
GuiControl, Main: Show%hideShow%, radio1244113855_1
GuiControl, Main: Enable%hideShow%, radio1244113855_1
GuiControl, Main: Show%hideShow%, radio1244113855_2
GuiControl, Main: Enable%hideShow%, radio1244113855_2
GuiControl, Main: Show%hideShow%, radio1371042200_1
GuiControl, Main: Enable%hideShow%, radio1371042200_1
GuiControl, Main: Show%hideShow%, radio1371042200_2
GuiControl, Main: Enable%hideShow%, radio1371042200_2
/*
The name of the executable that will recieve the output.
*/
GuiControl, Main: Show%hideShow%, text1439415306
/*
Automatically activate executable  (if it is running)  when controller is switched on.
*/
GuiControl, Main: Show%hideShow%, text1649409801
return
General>Setup:
GuiControl, Main: Show%hideShow%, edit968841594
GuiControl, Main: Enable%hideShow%, edit968841594
GuiControl, Main: Show%hideShow%, edit1484171716
GuiControl, Main: Enable%hideShow%, edit1484171716
GuiControl, Main: Show%hideShow%, edit1441011004
GuiControl, Main: Enable%hideShow%, edit1441011004
GuiControl, Main: Show%hideShow%, edit1136845697
GuiControl, Main: Enable%hideShow%, edit1136845697
GuiControl, Main: Show%hideShow%, text1820027441
GuiControl, Main: Show%hideShow%, text1761503059
GuiControl, Main: Show%hideShow%, text868645638
GuiControl, Main: Show%hideShow%, text303295627
/*
1 is linear, <1 lowers sensitivity away from center, >1 hightens sensitivity away center.
*/
GuiControl, Main: Show%hideShow%, text1950133817
/*
Range, (0,1). The center area (pink in the visual aid) where no output is sent.
*/
GuiControl, Main: Show%hideShow%, text1365655690
/*
ms. Snaps back to center when entering inner ring, and pauses. Set to -1 to disable.
*/
GuiControl, Main: Show%hideShow%, text1314749378
/*
Range, (0,Screen Height/2). Lower values corresponds to higher sensitivity.
*/
GuiControl, Main: Show%hideShow%, text68851252
return
General>Hotkeys:
GuiControl, Main: Show%hideShow%, text495210823
GuiControl, Main: Show%hideShow%, text199783574
GuiControl, Main: Show%hideShow%, text1265532956
GuiControl, Main: Show%hideShow%, hotkey26759803
GuiControl, Main: Enable%hideShow%, hotkey26759803
GuiControl, Main: Show%hideShow%, hotkey26759803_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey26759803_addWinkey
GuiControl, Main: Show%hideShow%, hotkey255211840
GuiControl, Main: Enable%hideShow%, hotkey255211840
GuiControl, Main: Show%hideShow%, hotkey255211840_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey255211840_addWinkey
GuiControl, Main: Show%hideShow%, hotkey2127896190
GuiControl, Main: Enable%hideShow%, hotkey2127896190
GuiControl, Main: Show%hideShow%, hotkey2127896190_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey2127896190_addWinkey
return
Mouse2Joystick:
/*
There is no input verification.
Follow instructions and don't try to break it.
*/
GuiControl, Main: Show%hideShow%, text938990667
return
Mouse2Joystick>Axes:
GuiControl, Main: Show%hideShow%, edit446078763
GuiControl, Main: Enable%hideShow%, edit446078763
GuiControl, Main: Show%hideShow%, text1772933493
GuiControl, Main: Show%hideShow%, text11683084
GuiControl, Main: Show%hideShow%, text1550313039
GuiControl, Main: Show%hideShow%, radio1025876589_1
GuiControl, Main: Enable%hideShow%, radio1025876589_1
GuiControl, Main: Show%hideShow%, radio1025876589_2
GuiControl, Main: Enable%hideShow%, radio1025876589_2
GuiControl, Main: Show%hideShow%, radio122217493_1
GuiControl, Main: Enable%hideShow%, radio122217493_1
GuiControl, Main: Show%hideShow%, radio122217493_2
GuiControl, Main: Enable%hideShow%, radio122217493_2
/*
Range: [0,45]. Defines the area where only one axis is used.
*/
GuiControl, Main: Show%hideShow%, text374447714
return
Mouse2Joystick>Keys:
GuiControl, Main: Show%hideShow%, edit1874406880
GuiControl, Main: Enable%hideShow%, edit1874406880
GuiControl, Main: Show%hideShow%, text906325482
GuiControl, Main: Show%hideShow%, text1019731688
GuiControl, Main: Show%hideShow%, hotkey932981360
GuiControl, Main: Enable%hideShow%, hotkey932981360
GuiControl, Main: Show%hideShow%, hotkey932981360_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey932981360_addWinkey

GuiControl, Main: Show%hideShow%, hotkey93298136
GuiControl, Main: Enable%hideShow%, hotkey93298136
GuiControl, Main: Show%hideShow%, hotkey93298136_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey93298136_addWinkey

/*
The key list is a comma delimited list of (ahk valid) keys, where each entry binds to a joystick button.
The first entry binds to the first joystick buttons, and so on. Blanks and modifers are allowed.
*/
GuiControl, Main: Show%hideShow%, text789866609
/*
Fix stick to current position:
*/
GuiControl, Main: Show%hideShow%, text191419274
GuiControl, Main: Show%hideShow%, text19141927
return
Mouse2Keyboard:
/*
There is no input verification.
Follow instructions and don't try to break it.
*/
GuiControl, Main: Show%hideShow%, text1220495721
return
Mouse2Keyboard>Keys:
GuiControl, Main: Show%hideShow%, text388795812
GuiControl, Main: Show%hideShow%, text483483623
GuiControl, Main: Show%hideShow%, hotkey1964265821
GuiControl, Main: Enable%hideShow%, hotkey1964265821
GuiControl, Main: Show%hideShow%, hotkey1964265821_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey1964265821_addWinkey
GuiControl, Main: Show%hideShow%, hotkey599253628
GuiControl, Main: Enable%hideShow%, hotkey599253628
GuiControl, Main: Show%hideShow%, hotkey599253628_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey599253628_addWinkey
GuiControl, Main: Show%hideShow%, hotkey1278963789
GuiControl, Main: Enable%hideShow%, hotkey1278963789
GuiControl, Main: Show%hideShow%, hotkey1278963789_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey1278963789_addWinkey
GuiControl, Main: Show%hideShow%, hotkey2130103637
GuiControl, Main: Enable%hideShow%, hotkey2130103637
GuiControl, Main: Show%hideShow%, hotkey2130103637_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey2130103637_addWinkey
GuiControl, Main: Show%hideShow%, hotkey225514912
GuiControl, Main: Enable%hideShow%, hotkey225514912
GuiControl, Main: Show%hideShow%, hotkey225514912_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey225514912_addWinkey
GuiControl, Main: Show%hideShow%, hotkey83004604
GuiControl, Main: Enable%hideShow%, hotkey83004604
GuiControl, Main: Show%hideShow%, hotkey83004604_addWinkey
GuiControl, Main: Enable%hideShow%, hotkey83004604_addWinkey
/*
Up
*/
GuiControl, Main: Show%hideShow%, text587730748
/*
Down
*/
GuiControl, Main: Show%hideShow%, text530033183
/*
Left
*/
GuiControl, Main: Show%hideShow%, text2143338622
/*
Right
*/
GuiControl, Main: Show%hideShow%, text172497039
/*
Left mouse button
*/
GuiControl, Main: Show%hideShow%, text996303547
/*
Right mouse button
*/
GuiControl, Main: Show%hideShow%, text863373581
return
Visual_aid:
GuiControl, Main: Show%hideShow%, checkbox1135789786
GuiControl, Main: Enable%hideShow%, checkbox1135789786
GuiControl, Main: Show%hideShow%, text1829586573
GuiControl, Main: Show%hideShow%, text833212790
GuiControl, Main: Show%hideShow%, text1505650515
GuiControl, Main: Show%hideShow%, radio2102688731_1
GuiControl, Main: Enable%hideShow%, radio2102688731_1
GuiControl, Main: Show%hideShow%, radio2102688731_2
GuiControl, Main: Enable%hideShow%, radio2102688731_2
GuiControl, Main: Show%hideShow%, radio2030676791_1
GuiControl, Main: Enable%hideShow%, radio2030676791_1
GuiControl, Main: Show%hideShow%, radio2030676791_2
GuiControl, Main: Enable%hideShow%, radio2030676791_2

; NNVA
GuiControl, Main: Show%hideShow%, text1612995781
GuiControl, Main: Show%hideShow%, radio487673732_1
GuiControl, Main: Enable%hideShow%, radio487673732_1
GuiControl, Main: Show%hideShow%, radio487673732_2
GuiControl, Main: Enable%hideShow%, radio487673732_2

return
TV_LoadTree(tree)
{
	Loop, Parse, tree,`n,`r
	{
		node=%A_LoopField%
		Loop, Parse, node,;
			head%A_Index%:=A_LoopField
		break
	}
	if !head2
		return
	parentID:=TV_Add(head2,,"+expand")
	load(head4,parentID)
	parentID:=TV_GetParent(parentID)
	load(head3,parentID)
return
}
load(relativeID,parentID)
{
	nextSibling=
	nextChild=
	nodeName=
	getNode(nextSibling,nextChild,nodeName,relativeID)
	if nodeName
		parentID:=TV_Add(nodeName,parentID,"+expand")
	if nextChild
	{
		load(nextChild,parentID)
	}
	if nextSibling
	{
		parentID:=TV_GetParent(parentID)
		load(nextSibling,parentID)
	}
	return
}
getNode(ByRef sibling, ByRef child, ByRef nodeName, nodeID)
{
	global tree
	firstLoop:=1
	Loop, Parse, tree,`n,`r
	{
		if firstLoop
		{
			firstLoop:=0
			continue
		}
		node:=A_LoopField
		Loop, Parse, node,;
		{
			id:=A_LoopField
			break
		}
		if (id=nodeID)
		{
			Loop, Parse, node,;
				node%A_Index%:=A_LoopField
			break
		}
	}
	nodeName:=node2
	sibling:=node3
	child:=node4
	return
}
selectionPath(id)
{
	TV_GetText(name,id)
	if !name
		return 0
	parentID := id
	Loop
	{
		parentID := TV_GetParent(parentID)
		if !parentID
			break
		parentName=
		TV_GetText(parentName, parentID)
		if parentName
			name = %parentName%>%name%
	}
	return name
}
readTreeString:
tree=
(
39872096;General;39872384;39872192
39872192;Setup;39872288;0
39872288;Hotkeys;0;0
39872384;Mouse2Joystick;39872960;39872480
39872480;Axes;39872576;0
39872576;Keys;0;0
39872960;Mouse2Keyboard;39873152;39873056
39873056;Keys;0;0
39873152;Visual aid;0;0
)
return

; Default settings in case problem reading/writing to file.
setSettingsToDefault:
	pairsDefault=
(
gameExe=notepad.exe
mouse2joystick=1
autoActivateGame=1
firstRun=1
r=160
k=0.35
fallBackPause=-1
nnp=1
controllerSwitchKey=#s
exitKey=#q
moveAidKey=#d
angularDeadZone=22
invertedX=0
invertedY=0
joystickButtonKeyList=
autoHoldStickKey=#f
fixRadiusKey=#r
upKey=w
downKey=s
leftKey=a
rightKey=d
LButtonReplacementKey=
RButtonReplacementKey=
kr=21
hideCursor=1
visualAidIsOn=1
autoPlaceVisualAid=1
nnVA=1
)
	Loop,Parse,pairsDefault,`n
	{
		StringSplit,keyValue,A_LoopField,=
		%keyValue1%:=keyValue2
	}
	Goto, readSettingsSkippedDueToError
return

