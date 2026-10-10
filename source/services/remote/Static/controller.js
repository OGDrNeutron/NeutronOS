const statusEl = document.getElementById("status");

let reconnectTimer = null;
let token = localStorage.getItem("neutronos-controller-token") || "";
let connected = false;

const heldButtons = new Set();
const repeatTimers = new Map();

const NAV_BUTTONS = new Set([
    "UP",
    "DOWN",
    "LEFT",
    "RIGHT"
]);

const REPEAT_DELAY_MS = 260;
const REPEAT_RATE_MS = 115;

async function pair() {
    const code = window.prompt("Enter the six-digit pairing code shown by NeutronOS");
    if (!code) return false;
    const deviceId = localStorage.getItem("neutronos-controller-device") || crypto.randomUUID();
    localStorage.setItem("neutronos-controller-device", deviceId);
    const response = await fetch("/api/pair", {method:"POST", headers:{"Content-Type":"application/json","X-NeutronOS-Device":deviceId}, body:JSON.stringify({code,deviceId})});
    if (!response.ok) return false;
    token = (await response.json()).token || "";
    if (token) localStorage.setItem("neutronos-controller-token", token);
    return Boolean(token);
}

async function connect() {
    if (!token && !(await pair())) { statusEl.textContent="pairing required"; statusEl.classList.add("error"); return; }
    try {
        let response=await fetch("/api/health",{headers:{"Authorization":"Bearer "+token}});
        if (response.status===401) { localStorage.removeItem("neutronos-controller-token"); token=""; if(await pair()) response=await fetch("/api/health",{headers:{"Authorization":"Bearer "+token}}); }
        connected=response.ok;
    } catch (_) { connected=false; }
    statusEl.textContent=connected?"connected":"disconnected";
    statusEl.classList.toggle("error",!connected);
    if(!connected) scheduleReconnect();
}

function scheduleReconnect() {
    if (reconnectTimer)
        return;

    reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        connect();
    }, 1200);
}

function vibrate(pattern = 14) {
    if (navigator.vibrate)
        navigator.vibrate(pattern);
}

function send(button, state = "press", extra = {}) {
    if (!button)
        return;

    if (connected) {
        fetch("/api/controller/event", {method:"POST", headers:{"Content-Type":"application/json","Authorization":"Bearer "+token}, body:JSON.stringify({
            type: "controller",
            button,
            state,
            ...extra,
            time: Date.now(),
            nonce: crypto.randomUUID()
        })}).then(response=>{if(response.status===401){connected=false;scheduleReconnect();}}).catch(()=>{connected=false;scheduleReconnect();});
    }

    if (state === "press") {
        if (button === "CIRCLE")
            vibrate([18, 22, 18]);
        else if (button === "TRIANGLE" || button === "OPTIONS")
            vibrate(24);
        else
            vibrate(14);
    }
}

function startRepeat(button) {
    if (!NAV_BUTTONS.has(button))
        return;

    stopRepeat(button);

    const delayTimer = setTimeout(() => {
        const rateTimer = setInterval(() => {
            if (heldButtons.has(button))
                send(button, "press");
            else
                stopRepeat(button);
        }, REPEAT_RATE_MS);

        repeatTimers.set(button, rateTimer);
    }, REPEAT_DELAY_MS);

    repeatTimers.set(button, delayTimer);
}

function stopRepeat(button) {
    if (!repeatTimers.has(button))
        return;

    const timer = repeatTimers.get(button);

    clearTimeout(timer);
    clearInterval(timer);

    repeatTimers.delete(button);
}

function pressButton(button, element = null) {
    if (!button)
        return;

    if (heldButtons.has(button))
        return;

    heldButtons.add(button);

    if (element)
        element.classList.add("active");

    send(button, "press");
    startRepeat(button);
}

function releaseButton(button, element = null) {
    if (!button)
        return;

    if (!heldButtons.has(button))
        return;

    heldButtons.delete(button);
    stopRepeat(button);

    if (element)
        element.classList.remove("active");

    send(button, "release");
}

function releaseAllButtons() {
    Array.from(heldButtons).forEach(button => {
        stopRepeat(button);
        send(button, "release");
    });

    heldButtons.clear();

    document.querySelectorAll("button.active").forEach(btn => {
        btn.classList.remove("active");
    });
}

/* ==========================================================
   BUTTONS
========================================================== */

document.querySelectorAll("button[data-btn]").forEach(btn => {
    const name = btn.dataset.btn;

    btn.addEventListener("pointerdown", e => {
        e.preventDefault();

        if (btn.setPointerCapture)
            btn.setPointerCapture(e.pointerId);

        pressButton(name, btn);
    });

    btn.addEventListener("pointerup", e => {
        e.preventDefault();
        releaseButton(name, btn);
    });

    btn.addEventListener("pointercancel", e => {
        e.preventDefault();
        releaseButton(name, btn);
    });

    btn.addEventListener("lostpointercapture", () => {
        releaseButton(name, btn);
    });
});

/* ==========================================================
   ANALOG STICKS
========================================================== */

document.querySelectorAll(".stick").forEach(stick => {
    const knob = stick.querySelector(".knob");
    const stickName = stick.dataset.stick;

    let active = false;
    let pointerId = null;

    let currentHorizontal = null;
    let currentVertical = null;

    function releaseStickDirections() {
        if (currentHorizontal) {
            releaseButton(currentHorizontal);
            currentHorizontal = null;
        }

        if (currentVertical) {
            releaseButton(currentVertical);
            currentVertical = null;
        }
    }

    function centerKnob() {
        knob.style.transform = "translate(0px, 0px)";

        releaseStickDirections();

        send(stickName, "move", {
            x: 0,
            y: 0
        });
    }

    function updateDirection(nextHorizontal, nextVertical) {
        if (nextHorizontal !== currentHorizontal) {
            if (currentHorizontal)
                releaseButton(currentHorizontal);

            currentHorizontal = nextHorizontal;

            if (currentHorizontal)
                pressButton(currentHorizontal);
        }

        if (nextVertical !== currentVertical) {
            if (currentVertical)
                releaseButton(currentVertical);

            currentVertical = nextVertical;

            if (currentVertical)
                pressButton(currentVertical);
        }
    }

    function move(clientX, clientY) {
        const rect = stick.getBoundingClientRect();

        const cx = rect.left + rect.width / 2;
        const cy = rect.top + rect.height / 2;

        let dx = clientX - cx;
        let dy = clientY - cy;

        const max = rect.width * 0.30;
        const dist = Math.sqrt(dx * dx + dy * dy);

        if (dist > max) {
            dx = dx / dist * max;
            dy = dy / dist * max;
        }

        knob.style.transform = `translate(${dx}px, ${dy}px)`;

        const x = Math.round((dx / max) * 100);
        const y = Math.round((dy / max) * 100);

        let nextHorizontal = null;
        let nextVertical = null;

        if (x <= -42)
            nextHorizontal = "LEFT";
        else if (x >= 42)
            nextHorizontal = "RIGHT";

        if (y <= -42)
            nextVertical = "UP";
        else if (y >= 42)
            nextVertical = "DOWN";

        updateDirection(nextHorizontal, nextVertical);

        send(stickName, "move", {
            x,
            y
        });
    }

    stick.addEventListener("pointerdown", e => {
        e.preventDefault();

        active = true;
        pointerId = e.pointerId;

        if (stick.setPointerCapture)
            stick.setPointerCapture(pointerId);

        stick.classList.add("active");

        vibrate(16);
        move(e.clientX, e.clientY);
    });

    stick.addEventListener("pointermove", e => {
        e.preventDefault();

        if (!active || e.pointerId !== pointerId)
            return;

        move(e.clientX, e.clientY);
    });

    function endStick(e) {
        e.preventDefault();

        if (!active)
            return;

        active = false;
        pointerId = null;

        stick.classList.remove("active");
        centerKnob();
    }

    stick.addEventListener("pointerup", endStick);
    stick.addEventListener("pointercancel", endStick);

    stick.addEventListener("lostpointercapture", () => {
        if (!active)
            return;

        active = false;
        pointerId = null;

        stick.classList.remove("active");
        centerKnob();
    });
});

/* ==========================================================
   SAFETY
========================================================== */

window.addEventListener("blur", releaseAllButtons);
window.addEventListener("pagehide", releaseAllButtons);

document.addEventListener("visibilitychange", () => {
    if (document.hidden)
        releaseAllButtons();
});

document.addEventListener("contextmenu", e => {
    e.preventDefault();
});

connect();
