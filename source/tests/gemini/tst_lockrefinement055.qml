import QtQuick
import QtTest
import "../../qml/gemini" as Gemini
TestCase {
    id:test;name:"Gemini055LockRefinement";when:windowShown;visible:true;width:1920;height:1080
    QtObject {
        id:host
        property bool loginSuccess:false
        property bool animationsEnabled:true
        property bool cardArmed:true
        property string errorText:""
        property string statusText:"Sequence gate armed"
        property var inputTokens:[]
        property bool secure:false
        property bool locked:false
        property var controllerBackend:null
        property string avatarSource:""
        property real unlockRippleScale:1
        property real unlockRippleOpacity:0
        function greetingPrefix(){return "GOOD AFTERNOON."}
        function currentDisplayName(){return "Gemini VM"}
        function currentAvatarSource(){return avatarSource}
        function selectFocused(){cardArmed=true}
        function loginSecurityIsSecure(){return secure}
        function isLockedOut(){return locked}
        function formatTime(t){return "0:00"}
        function lockoutSecondsRemaining(){return 0}
    }
    Rectangle{anchors.fill:parent;color:"#02060d"}
    Image{anchors.fill:parent;source:"../../themes/Default/background.png";fillMode:Image.PreserveAspectCrop}
    Rectangle{anchors.fill:parent;color:"#02060d";opacity:.22}
    Gemini.LockPresentation{id:lock;anchors.fill:parent;host:host}
    function find(item,name){if(item.objectName===name)return item;var c=item.children||[];for(var i=0;i<c.length;i++){var hit=find(c[i],name);if(hit)return hit}return null}
    function test_a_reference_geometry_and_live_clock(){
        var welcome=find(lock,"GeminiLockWelcome"),security=find(lock,"GeminiLockSecurityBadge"),clock=find(lock,"GeminiLockClock"),center=find(lock,"GeminiLockCenter")
        compare(welcome.x,43);compare(welcome.y,67);compare(welcome.width,417);compare(welcome.height,106)
        compare(security.x,welcome.x);verify(security.y>welcome.y+welcome.height)
        compare(clock.y,57);compare(clock.x,1211);compare(clock.width,419);compare(clock.height,166)
        compare(center.x+center.width/2,836);compare(center.width,660);compare(center.height,660)
        compare(find(lock,"GeminiLockUserIcon").width,170)
        compare(clock.localTime,Qt.formatDateTime(clock.now,"h:mm AP").slice(0,-clock.localPeriod.length-1));compare(clock.localDate,Qt.formatDateTime(clock.now,"ddd, MMM d, yyyy"))
        var before=clock.now.getTime();wait(1200);verify(clock.now.getTime()>before)
        verify(!find(lock,"GeminiLockControllerPanel").activeFocus)
        waitForRendering(lock);var capture=grabImage(test);compare(capture.width,1920);compare(capture.height,1080);capture.save("/tmp/gemini-055-lock-refined-unsecure.png")
        host.secure=true;wait(150);grabImage(test).save("/tmp/gemini-055-lock-refined-secure.png");host.secure=false
    }
    function test_b_independent_input_wakes_and_error(){
        var ring=find(lock,"GeminiLockRing");var before=ring.pulseCount;var turn=ring.turn
        for(var i=0;i<15;i++){var tokens=host.inputTokens.slice();tokens.push("X");host.inputTokens=tokens}
        compare(ring.pulseCount,before+15);verify(ring.wavesA.x<1&&ring.wavesD.z<1)
        wait(180);verify(ring.turn!==turn);verify(ring.wavesA.x>0)
        grabImage(test).save("/tmp/gemini-055-lock-input-waves.png")
        host.inputTokens=[];compare(ring.pulseCount,before+15)
        host.locked=true;host.inputTokens=["X"];compare(ring.pulseCount,before+15);host.locked=false;host.inputTokens=[]
        host.errorText="Incorrect controller passcode";wait(150);compare(lock.feedback,"error");grabImage(test).save("/tmp/gemini-055-lock-refined-error.png")
        tryCompare(lock,"feedback","neutral",3000);host.errorText=""
        host.loginSuccess=true;compare(lock.feedback,"success");wait(150);grabImage(test).save("/tmp/gemini-055-lock-refined-success.png");host.loginSuccess=false
    }
    function test_c_actual_sixty_second_eastward_rotation(){
        var clock=find(lock,"GeminiLockClock"),earth=find(lock,"GeminiLockClockEarth"),ring=find(lock,"GeminiLockRing")
        compare(clock.earthRotationPeriodMs,60000);compare(ring.rotationPeriodMs,42000)
        var start=clock.earthAngle;var time=Date.now();wait(15000)
        var quarter=(clock.earthAngle-start+360)%360;verify(Math.abs(quarter-90)<5,"Earth must advance eastward by 90 degrees per 15 seconds: "+quarter)
        compare(earth.spinAngle,clock.earthAngle)
        wait(45000);var elapsed=Date.now()-time;var phase=(clock.earthAngle-start+360)%360
        verify(phase<6||phase>354,"Earth completes its actual 60-second revolution: "+phase)
        verify(elapsed>=60000&&elapsed<62000)
        console.info("GEMINI_LOCK_EARTH_MEASURED",JSON.stringify({elapsedMs:elapsed,quarterDegrees:quarter,finalPhaseDegrees:phase,eastward:true}))
    }
    function test_d_authoritative_armed_visibility(){
        var ring=find(lock,"GeminiLockRing")
        host.inputTokens=[];host.cardArmed=false;wait(350);compare(ring.opacity,0);verify(!ring.visible)
        verify(find(lock,"GeminiEnergyAtom").visible)
        grabImage(test).save("/tmp/gemini-055-lock-final-disarmed.png")
        host.cardArmed=true;wait(350);verify(ring.visible&&ring.opacity>.7)
        grabImage(test).save("/tmp/gemini-055-lock-final-armed.png")
        host.cardArmed=false;wait(350);compare(ring.opacity,0);verify(!ring.visible)
        host.cardArmed=true;wait(350);host.loginSuccess=true;wait(350);verify(!ring.visible)
        host.loginSuccess=false;host.locked=true;wait(350);verify(!ring.visible)
        host.locked=false;host.cardArmed=false
    }
    function test_f_full_circular_avatar_and_custom_crop(){
        var card=find(lock,"GeminiLockUserIcon"),surface=find(lock,"GeminiLockAvatarSurface"),outline=find(lock,"GeminiLockAvatarOutline"),mask=find(lock,"GeminiLockAvatarMask"),avatar=find(lock,"GeminiLockAvatarImage")
        host.cardArmed=false;host.avatarSource="";wait(400);tryCompare(avatar,"status",Image.Ready)
        compare(card.width,170);compare(card.height,170)
        for(var item of [surface,outline,mask,avatar]){compare(item.width,card.width);compare(item.height,card.height);compare(item.x,0);compare(item.y,0)}
        compare(avatar.fillMode,Image.PreserveAspectCrop);compare(outline.border.width,4);verify(outline.z>surface.z)
        compare(avatar.sourceClipRect,Qt.rect(32,24,960,960))
        grabImage(test).save("/tmp/gemini-055-r2-default-avatar.png")
        host.avatarSource=Qt.resolvedUrl("qml-fixtures/crop-avatar055.svg");tryCompare(avatar,"status",Image.Ready);wait(250)
        compare(avatar.sourceClipRect,Qt.rect(0,0,0,0))
        // QtTest's item grab uses the untransformed origin for this scaled ancestor.
        // Sample the full composed window at actual mapped card coordinates.
        var pixel=grabImage(test);pixel.save("/tmp/gemini-055-r2-custom-avatar.png")
        function sample(x,y){var p=card.mapToItem(test,x,y);return {x:Math.round(p.x),y:Math.round(p.y)}}
        for(var point of [sample(85,85),sample(10,85),sample(160,85)]){verify(pixel.green(point.x,point.y)>200);verify(pixel.red(point.x,point.y)<20);verify(pixel.blue(point.x,point.y)<20)}
        var corner=sample(1,1);verify(pixel.green(corner.x,corner.y)<180,"Circular mask excludes the square corner")
        var edge=sample(85,2);verify(pixel.blue(edge.x,edge.y)>180,"Cyan outline remains over the card")
        host.avatarSource="";tryCompare(avatar,"status",Image.Ready)
    }
    function test_g_connected_housing_and_full_time(){
        var clock=find(lock,"GeminiLockClock"),housing=find(lock,"GeminiClockHousing"),planet=find(lock,"GeminiClockPlanetInstrument"),earth=find(lock,"GeminiLockClockEarth"),time=find(lock,"GeminiLockLocalTime"),period=find(lock,"GeminiLockMeridiem"),date=find(lock,"GeminiLockLocalDate")
        compare(housing.x,12);compare(housing.y,20);compare(housing.width,372*.75);compare(housing.height,126*.75);compare(planet.width,170);compare(planet.height,170);compare(planet.x,244);compare(planet.y,0)
        // The extended end is concealed beneath the unchanged planet, before its center.
        verify(housing.x+housing.width>planet.x+37.5);verify(housing.x+housing.width<planet.x+planet.width/2);verify(planet.z>housing.z)
        compare(earth.width,180);compare(earth.height,180);compare(earth.latitude,18);compare(earth.longitude,90)
        compare(clock.x+planet.x,1455);verify(clock.x+clock.width<=1630)
        waitForRendering(lock);wait(600);grabImage(test).save("/tmp/gemini-055-r3-clock-live.png")
        clock.settings=formatFixture;formatFixture.use24Hour=false;clock.now=new Date(2026,9,9,12,59,0)
        compare(time.text,"12:59");compare(period.text,"PM");verify(date.text.length>0)
        verify((period.x+period.width)*.75<housing.width-21);verify((date.x+date.width)*.75<housing.width-21)
        verify(housing.x+Math.max(period.x+period.width,date.x+date.width)*.75<planet.x-6,"Text remains clear of the stationary Earth")
        grabImage(test).save("/tmp/gemini-055-r3-clock-1259.png")
        var angle=clock.earthAngle;wait(200);verify(clock.earthAngle!==angle);compare(clock.earthRotationPeriodMs,60000)
        clock.now=new Date()
    }
    QtObject{id:formatFixture;property bool use24Hour:false}
    function test_e_system_time_format(){
        var clock=find(lock,"GeminiLockClock");clock.settings=formatFixture
        compare(clock.localTime,Qt.formatDateTime(clock.now,"h:mm AP").slice(0,-clock.localPeriod.length-1));verify(clock.localPeriod.length>0)
        formatFixture.use24Hour=true;compare(clock.localTime,Qt.formatDateTime(clock.now,"HH:mm"));compare(clock.localPeriod,"")
        verify(!find(lock,"GeminiLockMeridiem").visible);formatFixture.use24Hour=false
    }

}
