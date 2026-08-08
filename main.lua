-- name: Second Wind
-- description: A Deltarune-inspired recovery minigame that gives Mario one last chance after death.
--
-- Created by CrypticTM
-- 
-- WORK IN PROGRESS: Some things may not work right yet.

local REQUIRED_HITS = 3
local MAX_ATTEMPTS = 5

local BAR_SPEED = 0.025
local PERFECT_WINDOW = 0.075

local SUCCESS_DISPLAY_FRAMES = 75
local FAILURE_DISPLAY_FRAMES = 45
local RECOVERY_COOLDOWN = 180

local DIFFICULTY_NORMAL = 1
local DIFFICULTY_HARD = 2
local DIFFICULTY_EXPERT = 3

local STATE_IDLE = 0
local STATE_ACTIVE = 1
local STATE_SUCCESS = 2
local STATE_FAILED = 3

local secondWindState = STATE_IDLE
local secondWindEnabled = true
local secondWindDifficulty = DIFFICULTY_NORMAL

local secondWindHits = 0
local secondWindAttempts = MAX_ATTEMPTS

local timingPosition = 0
local timingDirection = 1

local resultTimer = 0
local cooldownTimer = 0

local hudAlpha = 0
local hitFlash = 0
local missFlash = 0

local savedPosition = nil
local savedFaceAngle = 0

local recoveryMario = nil

local deathWasIntercepted = false
local allowNormalDeath = false
local cameraRecoveryTimer = 0

gGlobalSyncTable.secondWindEnabled = true
gGlobalSyncTable.secondWindDifficulty = DIFFICULTY_NORMAL

for i = 0, MAX_PLAYERS - 1 do
    gPlayerSyncTable[i].secondWindAvailable = true
    gPlayerSyncTable[i].secondWindRecovered = false
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end

local function reset_saved_position()
    savedPosition = nil
    savedFaceAngle = 0
end

local function save_position(m)
    if m.pos == nil then
        return
    end

    savedPosition = {
        x = m.pos.x,
        y = m.pos.y,
        z = m.pos.z
    }

    savedFaceAngle = m.faceAngle.y
end

local function restore_position(m)
    if savedPosition == nil then
        return false
    end

    m.pos.x = savedPosition.x
    m.pos.y = savedPosition.y
    m.pos.z = savedPosition.z

    m.faceAngle.y = savedFaceAngle

    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    m.forwardVel = 0

    return true
end

local function reset_player_sync()
    gPlayerSyncTable[0].secondWindAvailable = true
    gPlayerSyncTable[0].secondWindRecovered = false
end

local function reset_minigame()
    secondWindState = STATE_IDLE

    secondWindHits = 0
    secondWindAttempts = MAX_ATTEMPTS

    timingPosition = 0
    timingDirection = 1

    resultTimer = 0

    hudAlpha = 0
    hitFlash = 0
    missFlash = 0

    recoveryMario = nil

    deathWasIntercepted = false
    allowNormalDeath = false
    cameraRecoveryTimer = 0
end

local function get_bar_speed()
    if secondWindDifficulty == DIFFICULTY_HARD then
        return BAR_SPEED * 1.22
    end

    if secondWindDifficulty == DIFFICULTY_EXPERT then
        return BAR_SPEED * 1.48
    end

    return BAR_SPEED
end

local function get_perfect_window()
    if secondWindDifficulty == DIFFICULTY_HARD then
        return PERFECT_WINDOW * 0.82
    end

    if secondWindDifficulty == DIFFICULTY_EXPERT then
        return PERFECT_WINDOW * 0.66
    end

    return PERFECT_WINDOW
end

local function is_second_wind_available()
    if not secondWindEnabled then
        return false
    end

    if not gGlobalSyncTable.secondWindEnabled then
        return false
    end

    if cooldownTimer > 0 then
        return false
    end

    if secondWindState ~= STATE_IDLE then
        return false
    end

    if not gPlayerSyncTable[0].secondWindAvailable then
        return false
    end

    if savedPosition == nil then
        return false
    end

    return true
end

local function start_minigame(m)
    if not is_second_wind_available() then
        return false
    end

    recoveryMario = m

    secondWindState = STATE_ACTIVE

    secondWindHits = 0
    secondWindAttempts = MAX_ATTEMPTS

    timingPosition = 0
    timingDirection = 1

    resultTimer = 0

    hudAlpha = 0
    hitFlash = 0
    missFlash = 0

    deathWasIntercepted = true
    allowNormalDeath = false
    cameraRecoveryTimer = 0

    m.health = 0x880
    m.hurtCounter = 0
    m.invincTimer = 0

    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    m.forwardVel = 0

    set_mario_action(m, ACT_IDLE, 0)

    return true
end

local function timing_is_good()
    return math.abs(
        timingPosition - 0.5
    ) <= get_perfect_window()
end

local function successful_hit()
    secondWindHits = secondWindHits + 1
    hitFlash = 10

    timingPosition = 0
    timingDirection = 1

    if secondWindHits >= REQUIRED_HITS then
        secondWindState = STATE_SUCCESS
        resultTimer = SUCCESS_DISPLAY_FRAMES
    end
end

local function failed_hit()
    secondWindAttempts =
        secondWindAttempts - 1

    missFlash = 10

    timingPosition = 0
    timingDirection = 1

    if secondWindAttempts <= 0 then
        secondWindState = STATE_FAILED
        resultTimer = FAILURE_DISPLAY_FRAMES
    end
end

local function update_minigame(m)
    if secondWindState ~= STATE_ACTIVE then
        return
    end

    timingPosition =
        timingPosition +
        get_bar_speed() *
        timingDirection

    if timingPosition >= 1 then
        timingPosition = 1
        timingDirection = -1
    elseif timingPosition <= 0 then
        timingPosition = 0
        timingDirection = 1
    end

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        if timing_is_good() then
            successful_hit()
        else
            failed_hit()
        end
    end

    m.health = 0x880
    m.hurtCounter = 0

    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    m.forwardVel = 0

    if m.action ~= ACT_IDLE then
        set_mario_action(m, ACT_IDLE, 0)
    end
end

local function release_camera(m)
    if m == nil then
        return
    end

    cameraRecoveryTimer = 15

    set_mario_action(m, ACT_IDLE, 0)

    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    m.forwardVel = 0

    m.health = 0x880
    m.hurtCounter = 0
end

local function finish_success(m)
    if m == nil then
        reset_minigame()
        return
    end

    if not restore_position(m) then
        reset_minigame()
        return
    end

    m.health = 0x880
    m.hurtCounter = 0
    m.invincTimer = 90

    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    m.forwardVel = 0

    m.actionTimer = 0

    set_mario_action(
        m,
        ACT_IDLE,
        0
    )

    gPlayerSyncTable[0].secondWindAvailable = false
    gPlayerSyncTable[0].secondWindRecovered = true

    cooldownTimer = RECOVERY_COOLDOWN

    release_camera(m)

    secondWindState = STATE_IDLE
    resultTimer = 0
    hudAlpha = 0

    recoveryMario = nil
    deathWasIntercepted = false
    allowNormalDeath = false

    djui_chat_message_create(
        "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ YOU'RE BACK!"
    )
end

local function finish_failure(m)
    if m == nil then
        reset_minigame()
        return
    end

    release_camera(m)

    recoveryMario = nil

    secondWindState = STATE_IDLE
    resultTimer = 0
    hudAlpha = 0

    deathWasIntercepted = false
    allowNormalDeath = true

    gPlayerSyncTable[0].secondWindAvailable = false
    gPlayerSyncTable[0].secondWindRecovered = false

    reset_saved_position()

    m.health = 0
    m.hurtCounter = 0

    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    m.forwardVel = 0

    set_mario_action(
        m,
        ACT_DEATH_EXIT_LAND,
        0
    )
end

local function update_result_state()
    if secondWindState ~= STATE_SUCCESS and
        secondWindState ~= STATE_FAILED then
        return
    end

    resultTimer =
        math.max(
            0,
            resultTimer - 1
        )

    if resultTimer > 0 then
        return
    end

    if secondWindState == STATE_SUCCESS then
        finish_success(recoveryMario)
        return
    end

    if secondWindState == STATE_FAILED then
        finish_failure(recoveryMario)
    end
end

local function mario_update(m)
    if m.playerIndex ~= 0 then
        return
    end

    if cooldownTimer > 0 then
        cooldownTimer =
            cooldownTimer - 1
    end

    if cameraRecoveryTimer > 0 then
        cameraRecoveryTimer =
            cameraRecoveryTimer - 1

        if secondWindState == STATE_IDLE then
            m.health = 0x880
            m.hurtCounter = 0
            m.vel.x = 0
            m.vel.y = 0
            m.vel.z = 0
            m.forwardVel = 0

            if m.action ~= ACT_IDLE then
                set_mario_action(
                    m,
                    ACT_IDLE,
                    0
                )
            end
        end
    end

    if hitFlash > 0 then
        hitFlash = hitFlash - 1
    end

    if missFlash > 0 then
        missFlash = missFlash - 1
    end

    if secondWindState == STATE_IDLE then
        if m.health > 0x400 then
            save_position(m)
        end

        return
    end

    if secondWindState == STATE_ACTIVE then
        update_minigame(m)
        return
    end

    update_result_state()
end

local function before_mario_update(m)
    if m.playerIndex ~= 0 then
        return
    end

    if secondWindState ~= STATE_ACTIVE then
        return
    end

    m.health = 0x880
    m.hurtCounter = 0

    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    m.forwardVel = 0

    if m.action ~= ACT_IDLE then
        set_mario_action(
            m,
            ACT_IDLE,
            0
        )
    end
end

local function before_set_mario_action(
    m,
    incomingAction,
    actionArg
)
    if m.playerIndex ~= 0 then
        return
    end

    if secondWindState ~= STATE_ACTIVE then
        return
    end

    if incomingAction == ACT_DEATH_EXIT_LAND or
        incomingAction == ACT_DEATH_ON_STOMACH or
        incomingAction == ACT_DEATH_ON_BACK or
        incomingAction == ACT_DEATH_QUICKSAND or
        incomingAction == ACT_DEATH_EXIT then
        return 1
    end

    return 1
end

local function on_camera_mode(
    camera,
    mode,
    frames
)
    if secondWindState ~= STATE_ACTIVE then
        return
    end

    return false
end

local function on_change_camera_angle(mode)
    if secondWindState ~= STATE_ACTIVE then
        return
    end

    return false
end

local function on_death(m)
    if m.playerIndex ~= 0 then
        return
    end

    if allowNormalDeath then
        allowNormalDeath = false
        return
    end

    if secondWindState ~= STATE_IDLE then
        return false
    end

    if not is_second_wind_available() then
        return
    end

    if start_minigame(m) then
        return false
    end
end

local function on_level_init(
    levelType,
    levelNum,
    areaIdx,
    nodeId,
    arg
)
    reset_minigame()
    reset_saved_position()

    cooldownTimer = 0

    reset_player_sync()
end

local function update_second_wind()
    if secondWindState == STATE_IDLE then
        return
    end

    if hudAlpha < 255 then
        hudAlpha =
            math.min(
                255,
                hudAlpha + 24
            )
    end
end

local function hud_width()
    return djui_hud_get_screen_width()
end

local function hud_height()
    return djui_hud_get_screen_height()
end

local function text_width(text, scale)
    return
        djui_hud_measure_text(text) *
        scale
end

local function centered_x(text, scale)
    return
        (
            hud_width() -
            text_width(text, scale)
        ) / 2
end

local function draw_text(
    text,
    x,
    y,
    scale,
    r,
    g,
    b,
    a
)
    djui_hud_set_color(
        r,
        g,
        b,
        a
    )

    djui_hud_print_text(
        text,
        x,
        y,
        scale
    )
end

local function draw_centered_text(
    text,
    y,
    scale,
    r,
    g,
    b,
    a
)
    draw_text(
        text,
        centered_x(text, scale),
        y,
        scale,
        r,
        g,
        b,
        a
    )
end

local function draw_rect(
    x,
    y,
    width,
    height,
    r,
    g,
    b,
    a
)
    djui_hud_set_color(
        r,
        g,
        b,
        a
    )

    djui_hud_render_rect(
        x,
        y,
        width,
        height
    )
end

local function draw_outline(
    x,
    y,
    width,
    height,
    r,
    g,
    b,
    a
)
    draw_rect(
        x,
        y,
        width,
        2,
        r,
        g,
        b,
        a
    )

    draw_rect(
        x,
        y + height - 2,
        width,
        2,
        r,
        g,
        b,
        a
    )

    draw_rect(
        x,
        y,
        2,
        height,
        r,
        g,
        b,
        a
    )

    draw_rect(
        x + width - 2,
        y,
        2,
        height,
        r,
        g,
        b,
        a
    )
end

local function draw_panel(
    x,
    y,
    width,
    height,
    alpha
)
    draw_rect(
        x + 6,
        y + 7,
        width,
        height,
        0,
        0,
        0,
        alpha * 0.55
    )

    draw_rect(
        x,
        y,
        width,
        height,
        8,
        8,
        10,
        alpha * 0.98
    )

    draw_outline(
        x,
        y,
        width,
        height,
        235,
        235,
        235,
        alpha
    )

    draw_rect(
        x + 3,
        y + 3,
        width - 6,
        2,
        255,
        255,
        255,
        alpha * 0.14
    )
end

local function draw_heart(
    x,
    y,
    scale,
    r,
    g,
    b,
    a
)
    local size = 5 * scale

    draw_rect(
        x - size * 1.5,
        y - size,
        size,
        size,
        r,
        g,
        b,
        a
    )

    draw_rect(
        x + size * 0.5,
        y - size,
        size,
        size,
        r,
        g,
        b,
        a
    )

    draw_rect(
        x - size,
        y,
        size * 2,
        size,
        r,
        g,
        b,
        a
    )

    draw_rect(
        x - size * 0.5,
        y + size,
        size,
        size,
        r,
        g,
        b,
        a
    )
end

local function draw_heart_outline(
    x,
    y,
    scale,
    alpha
)
    local size = 5 * scale

    draw_outline(
        x - size * 1.5,
        y - size,
        size,
        size,
        120,
        120,
        120,
        alpha
    )

    draw_outline(
        x + size * 0.5,
        y - size,
        size,
        size,
        120,
        120,
        120,
        alpha
    )

    draw_outline(
        x - size,
        y,
        size * 2,
        size,
        120,
        120,
        120,
        alpha
    )
end

local function draw_target_zone(
    x,
    y,
    width,
    height,
    alpha
)
    local targetWidth =
        width *
        get_perfect_window() *
        2

    local targetX =
        x +
        (
            width -
            targetWidth
        ) / 2

    draw_rect(
        targetX,
        y - 5,
        targetWidth,
        height + 10,
        255,
        255,
        255,
        alpha * 0.10
    )

    draw_outline(
        targetX,
        y - 5,
        targetWidth,
        height + 10,
        255,
        255,
        255,
        alpha * 0.72
    )
end

local function draw_timing_line(
    x,
    y,
    width,
    alpha
)
    draw_rect(
        x,
        y,
        width,
        7,
        25,
        25,
        28,
        alpha
    )

    draw_target_zone(
        x,
        y,
        width,
        7,
        alpha
    )

    local heartX =
        x +
        width *
        timingPosition

    draw_heart(
        heartX,
        y - 4,
        1.0,
        255,
        255,
        255,
        alpha
    )
end

local function draw_attempts(
    x,
    y,
    alpha
)
    for i = 1, MAX_ATTEMPTS do
        local heartX =
            x +
            (
                i - 1
            ) *
            23

        if i <= secondWindAttempts then
            draw_heart(
                heartX,
                y,
                0.65,
                255,
                255,
                255,
                alpha
            )
        else
            draw_heart_outline(
                heartX,
                y,
                0.65,
                alpha
            )
        end
    end
end

local function draw_hits(
    y,
    alpha
)
    local spacing = 30

    local startX =
        hud_width() / 2 -
        (
            (
                REQUIRED_HITS - 1
            ) *
            spacing
        ) / 2

    for i = 1, REQUIRED_HITS do
        local x =
            startX +
            (
                i - 1
            ) *
            spacing

        if i <= secondWindHits then
            draw_heart(
                x,
                y,
                0.72,
                255,
                255,
                255,
                alpha
            )
        else
            draw_heart_outline(
                x,
                y,
                0.72,
                alpha
            )
        end
    end
end

local function draw_active_hud()
    local width =
        math.min(
            470,
            hud_width() - 24
        )

    local height = 190

    local x =
        (
            hud_width() -
            width
        ) / 2

    local y =
        hud_height() * 0.57

    draw_panel(
        x,
        y,
        width,
        height,
        hudAlpha
    )

    draw_centered_text(
        "SECOND WIND",
        y + 12,
        0.72,
        255,
        255,
        255,
        hudAlpha
    )

    draw_centered_text(
        "HIT THE CENTER THREE TIMES",
        y + 39,
        0.32,
        150,
        150,
        150,
        hudAlpha
    )

    draw_timing_line(
        x + 40,
        y + 73,
        width - 80,
        hudAlpha
    )

    draw_hits(
        y + 108,
        hudAlpha
    )

    draw_attempts(
        x + 45,
        y + 137,
        hudAlpha
    )

    draw_text(
        "A",
        x + width - 60,
        y + 132,
        0.55,
        255,
        255,
        255,
        hudAlpha
    )

    draw_text(
        "PRESS",
        x + width - 82,
        y + 151,
        0.25,
        130,
        130,
        130,
        hudAlpha
    )

    if hitFlash > 0 then
        draw_centered_text(
            "GOOD",
            y + 164,
            0.30,
            255,
            255,
            255,
            hitFlash * 22
        )
    elseif missFlash > 0 then
        draw_centered_text(
            "MISS",
            y + 164,
            0.30,
            150,
            150,
            150,
            missFlash * 22
        )
    end
end

local function draw_success_hud()
    local width =
        math.min(
            430,
            hud_width() - 24
        )

    local height = 150

    local x =
        (
            hud_width() -
            width
        ) / 2

    local y =
        hud_height() * 0.57

    draw_panel(
        x,
        y,
        width,
        height,
        255
    )

    draw_centered_text(
        "SECOND WIND",
        y + 14,
        0.72,
        255,
        255,
        255,
        255
    )

    draw_heart(
        hud_width() / 2,
        y + 59,
        1.15,
        255,
        255,
        255,
        255
    )

    draw_centered_text(
        "YOU'RE BACK!",
        y + 84,
        0.62,
        255,
        255,
        255
    )

    draw_centered_text(
        "GET BACK IN THERE",
        y + 119,
        0.32,
        150,
        150,
        150,
        255
    )
end

local function draw_failure_hud()
    local width =
        math.min(
            430,
            hud_width() - 24
        )

    local height = 150

    local x =
        (
            hud_width() -
            width
        ) / 2

    local y =
        hud_height() * 0.57

    draw_panel(
        x,
        y,
        width,
        height,
        255
    )

    draw_centered_text(
        "SECOND WIND",
        y + 14,
        0.72,
        255,
        255,
        255,
        255
    )

    draw_centered_text(
        "NOT THIS TIME",
        y + 54,
        0.48,
        180,
        180,
        180,
        255
    )

    draw_centered_text(
        "BACK TO THE NORMAL DEATH",
        y + 87,
        0.30,
        125,
        125,
        125,
        255
    )

    draw_centered_text(
        "GET READY",
        y + 114,
        0.28,
        110,
        110,
        110,
        255
    )
end

local function render_second_wind()
    if secondWindState == STATE_IDLE then
        return
    end

    djui_hud_set_resolution(
        RESOLUTION_DJUI
    )

    djui_hud_set_font(
        FONT_NORMAL
    )

    if secondWindState == STATE_ACTIVE then
        draw_active_hud()
        return
    end

    if secondWindState == STATE_SUCCESS then
        draw_success_hud()
        return
    end

    if secondWindState == STATE_FAILED then
        draw_failure_hud()
    end
end

local function set_enabled(
    index,
    value
)
    if not network_is_server() then
        return
    end

    secondWindEnabled = value
    gGlobalSyncTable.secondWindEnabled = value

    if not value then
        reset_minigame()
        reset_saved_position()
    end
end

local function set_difficulty(
    index,
    value
)
    if not network_is_server() then
        return
    end

    secondWindDifficulty =
        clamp(
            value,
            DIFFICULTY_NORMAL,
            DIFFICULTY_EXPERT
        )

    gGlobalSyncTable.secondWindDifficulty =
        secondWindDifficulty
end

local function reset_second_wind(
    index
)
    if index ~= 0 then
        return
    end

    if not network_is_server() then
        djui_chat_message_create(
            "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ Only the host can reset it."
        )

        return
    end

    reset_minigame()
    reset_saved_position()

    cooldownTimer = 0

    reset_player_sync()

    djui_chat_message_create(
        "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ Reset."
    )
end

local function second_wind_command(msg)
    msg =
        string.lower(
            msg or ""
        )

    if msg == "reset" then
        reset_second_wind(0)
        return true
    end

    if msg == "status" then
        local status = "READY"

        if secondWindState == STATE_ACTIVE then
            status = "ACTIVE"
        elseif secondWindState == STATE_SUCCESS then
            status = "SUCCESS"
        elseif secondWindState == STATE_FAILED then
            status = "FAILED"
        end

        djui_chat_message_create(
            "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ Status: " ..
            status
        )

        return true
    end

    djui_chat_message_create(
        "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ /secondwind reset"
    )

    djui_chat_message_create(
        "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ /secondwind status"
    )

    return true
end

local function initialize_second_wind()
    secondWindEnabled = true
    secondWindDifficulty = DIFFICULTY_NORMAL

    if network_is_server() then
        gGlobalSyncTable.secondWindEnabled = true
        gGlobalSyncTable.secondWindDifficulty =
            DIFFICULTY_NORMAL
    end

    reset_minigame()
    reset_saved_position()

    cooldownTimer = 0

    reset_player_sync()
end

hook_event(
    HOOK_MARIO_UPDATE,
    mario_update
)

hook_event(
    HOOK_BEFORE_MARIO_UPDATE,
    before_mario_update
)

hook_event(
    HOOK_BEFORE_SET_MARIO_ACTION,
    before_set_mario_action
)

hook_event(
    HOOK_ON_SET_CAMERA_MODE,
    on_camera_mode
)

hook_event(
    HOOK_ON_CHANGE_CAMERA_ANGLE,
    on_change_camera_angle
)

hook_event(
    HOOK_ON_DEATH,
    on_death
)

hook_event(
    HOOK_ON_LEVEL_INIT,
    on_level_init
)

hook_event(
    HOOK_UPDATE,
    update_second_wind
)

hook_event(
    HOOK_ON_HUD_RENDER,
    render_second_wind
)

hook_chat_command(
    "secondwind",
    "[reset|status]",
    second_wind_command
)

hook_mod_menu_text(
    "Second Wind"
)

hook_mod_menu_checkbox(
    "Enabled",
    true,
    set_enabled
)

hook_mod_menu_text(
    "Modifiers"
)

hook_mod_menu_slider(
    "Difficulty",
    DIFFICULTY_NORMAL,
    DIFFICULTY_NORMAL,
    DIFFICULTY_EXPERT,
    set_difficulty
)

hook_mod_menu_button(
    "Reset Second Wind",
    reset_second_wind
)

initialize_second_wind()

print("[Second Wind] Created by CrypticTM")
print("[Second Wind] Work in progress.")
print("[Second Wind] Loaded.")