-- name: Second Wind
-- description: A cooperative recovery system where players can earn a second chance through a three-hit timing challenge.\n\nCreated by CrypticTM
-- \n-- WORK IN PROGRESS: Some things may not work right yet.

local SECOND_WIND_ENABLED = true
local SECOND_WIND_ATTEMPTS = 3
local SECOND_WIND_WINDOW = 12
local SECOND_WIND_SPEED = 3
local SECOND_WIND_COOLDOWN = 180
local SECOND_WIND_REQUIRED_HITS = 3
local SECOND_WIND_RETRY_DELAY = 12
local SECOND_WIND_POPUP_FRAMES = 75
local SECOND_WIND_SUCCESS_FRAMES = 70
local SECOND_WIND_FAIL_FRAMES = 70

local SECOND_WIND_STATE_IDLE = 0
local SECOND_WIND_STATE_ACTIVE = 1
local SECOND_WIND_STATE_SUCCESS = 2
local SECOND_WIND_STATE_FAILED = 3

local secondWindState = SECOND_WIND_STATE_IDLE
local secondWindHits = 0
local secondWindAttempts = SECOND_WIND_ATTEMPTS
local secondWindPosition = 0
local secondWindDirection = 1
local secondWindTimer = 0
local secondWindResultTimer = 0
local secondWindCooldown = 0
local secondWindLastHit = false
local secondWindWasActive = false
local secondWindSavedPosition = nil
local secondWindSavedAngle = 0
local secondWindSavedArea = 1
local secondWindSavedLevel = LEVEL_CASTLE_GROUNDS
local secondWindHudAlpha = 0
local secondWindPulse = 0
local secondWindTestRequested = false

local secondWindMenuEnabled = true
local secondWindMenuDifficulty = 1

gGlobalSyncTable.secondWindEnabled = true
gGlobalSyncTable.secondWindDifficulty = 1

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

local function copy_position(m)
    return {
        x = m.pos.x,
        y = m.pos.y,
        z = m.pos.z
    }
end

local function restore_position(m)
    if secondWindSavedPosition == nil then
        return false
    end

    m.pos.x = secondWindSavedPosition.x
    m.pos.y = secondWindSavedPosition.y
    m.pos.z = secondWindSavedPosition.z
    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    m.forwardVel = 0
    m.faceAngle.y = secondWindSavedAngle

    return true
end

local function get_difficulty_window()
    if secondWindMenuDifficulty == 1 then
        return SECOND_WIND_WINDOW
    end

    if secondWindMenuDifficulty == 2 then
        return math.max(7, SECOND_WIND_WINDOW - 3)
    end

    return math.max(4, SECOND_WIND_WINDOW - 6)
end

local function get_difficulty_speed()
    if secondWindMenuDifficulty == 1 then
        return SECOND_WIND_SPEED
    end

    if secondWindMenuDifficulty == 2 then
        return SECOND_WIND_SPEED + 1
    end

    return SECOND_WIND_SPEED + 2
end

local function reset_second_wind()
    secondWindState = SECOND_WIND_STATE_IDLE
    secondWindHits = 0
    secondWindAttempts = SECOND_WIND_ATTEMPTS
    secondWindPosition = 0
    secondWindDirection = 1
    secondWindTimer = 0
    secondWindResultTimer = 0
    secondWindLastHit = false
    secondWindWasActive = false
    secondWindHudAlpha = 0
    secondWindPulse = 0
end

local function can_start_second_wind()
    if not secondWindMenuEnabled then
        return false
    end

    if not gGlobalSyncTable.secondWindEnabled then
        return false
    end

    if secondWindState ~= SECOND_WIND_STATE_IDLE then
        return false
    end

    if secondWindCooldown > 0 then
        return false
    end

    if not gPlayerSyncTable[0].secondWindAvailable then
        return false
    end

    return true
end

local function start_second_wind(m)
    if not can_start_second_wind() then
        return false
    end

    secondWindSavedPosition = copy_position(m)
    secondWindSavedAngle = m.faceAngle.y
    secondWindSavedArea = gNetworkPlayers[0].currAreaIndex
    secondWindSavedLevel = gNetworkPlayers[0].currLevelNum

    secondWindState = SECOND_WIND_STATE_ACTIVE
    secondWindHits = 0
    secondWindAttempts = SECOND_WIND_ATTEMPTS
    secondWindPosition = 0
    secondWindDirection = 1
    secondWindTimer = 0
    secondWindResultTimer = 0
    secondWindLastHit = false
    secondWindWasActive = true
    secondWindHudAlpha = 0
    secondWindPulse = 0

    return true
end

local function finish_second_wind(m)
    if secondWindState ~= SECOND_WIND_STATE_SUCCESS then
        return
    end

    if secondWindResultTimer > 0 then
        return
    end

    if not restore_position(m) then
        return
    end

    m.health = 0x880
    m.hurtCounter = 0
    m.invincTimer = 90
    m.actionTimer = 0
    m.prevAction = ACT_IDLE
    m.action = ACT_IDLE
    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    m.forwardVel = 0

    gPlayerSyncTable[0].secondWindAvailable = false
    gPlayerSyncTable[0].secondWindRecovered = true

    secondWindCooldown = SECOND_WIND_COOLDOWN
    secondWindResultTimer = SECOND_WIND_SUCCESS_FRAMES
end

local function fail_second_wind()
    secondWindState = SECOND_WIND_STATE_FAILED
    secondWindResultTimer = SECOND_WIND_FAIL_FRAMES
    secondWindHudAlpha = 255
end

local function register_hit()
    secondWindHits = secondWindHits + 1
    secondWindLastHit = true
    secondWindTimer = 0
    secondWindPulse = 18

    if secondWindHits >= SECOND_WIND_REQUIRED_HITS then
        secondWindState = SECOND_WIND_STATE_SUCCESS
        secondWindResultTimer = SECOND_WIND_SUCCESS_FRAMES
        return
    end

    secondWindPosition = 0
    secondWindDirection = 1
end

local function register_miss()
    secondWindAttempts = secondWindAttempts - 1
    secondWindLastHit = false
    secondWindTimer = 0
    secondWindPulse = 10

    if secondWindAttempts <= 0 then
        fail_second_wind()
        return
    end

    secondWindPosition = 0
    secondWindDirection = 1
end

local function get_input_pressed(m)
    return (m.controller.buttonPressed & A_BUTTON) ~= 0
end

local function is_inside_target()
    local targetCenter = 0.5
    local window = get_difficulty_window() / 100

    return math.abs(secondWindPosition - targetCenter) <= window
end

local function update_second_wind_game(m)
    if secondWindState ~= SECOND_WIND_STATE_ACTIVE then
        return
    end

    secondWindTimer = secondWindTimer + 1

    local speed = get_difficulty_speed() / 100

    secondWindPosition =
        secondWindPosition +
        (speed * secondWindDirection)

    if secondWindPosition >= 1 then
        secondWindPosition = 1
        secondWindDirection = -1
    elseif secondWindPosition <= 0 then
        secondWindPosition = 0
        secondWindDirection = 1
    end

    if get_input_pressed(m) then
        if is_inside_target() then
            register_hit()
        else
            register_miss()
        end
    end
end

local function update_second_wind_result(m)
    if secondWindState == SECOND_WIND_STATE_SUCCESS then
        if secondWindResultTimer > 0 then
            secondWindResultTimer = secondWindResultTimer - 1
        end

        if secondWindResultTimer <= 0 then
            finish_second_wind(m)
        end

        return
    end

    if secondWindState == SECOND_WIND_STATE_FAILED then
        if secondWindResultTimer > 0 then
            secondWindResultTimer = secondWindResultTimer - 1
        end

        if secondWindResultTimer <= 0 then
            reset_second_wind()
        end
    end
end

local function update_second_wind_cooldown()
    if secondWindCooldown > 0 then
        secondWindCooldown = secondWindCooldown - 1
    end
end

local function update_saved_position(m)
    if secondWindState ~= SECOND_WIND_STATE_IDLE then
        return
    end

    if secondWindCooldown > 0 then
        return
    end

    if m.action == ACT_DEATH_EXIT or
        m.action == ACT_DEATH_ON_BACK or
        m.action == ACT_DEATH_ON_STOMACH then
        return
    end

    if m.health <= 0x100 then
        return
    end

    secondWindSavedPosition = copy_position(m)
    secondWindSavedAngle = m.faceAngle.y
    secondWindSavedArea = gNetworkPlayers[0].currAreaIndex
    secondWindSavedLevel = gNetworkPlayers[0].currLevelNum
end

local function mario_update(m)
    if m.playerIndex ~= 0 then
        return
    end

    update_second_wind_cooldown()
    update_saved_position(m)

    if secondWindState == SECOND_WIND_STATE_ACTIVE then
        update_second_wind_game(m)

        m.vel.x = 0
        m.vel.y = 0
        m.vel.z = 0
        m.forwardVel = 0

        return
    end

    update_second_wind_result(m)
end

local function on_death(m)
    if m.playerIndex ~= 0 then
        return
    end

    if secondWindState ~= SECOND_WIND_STATE_IDLE then
        return
    end

    if not can_start_second_wind() then
        return
    end

    if start_second_wind(m) then
        return false
    end
end

local function on_level_init()
    reset_second_wind()

    secondWindCooldown = 0
    secondWindSavedPosition = nil

    gPlayerSyncTable[0].secondWindAvailable = true
    gPlayerSyncTable[0].secondWindRecovered = false
end

local function draw_text_centered(text, y, scale, r, g, b, a)
    local width = djui_hud_measure_text(text) * scale
    local screenWidth = djui_hud_get_screen_width()
    local x = (screenWidth - width) / 2

    djui_hud_set_color(r, g, b, a)
    djui_hud_print_text(text, x, y, scale)
end

local function draw_rect(x, y, width, height, r, g, b, a)
    djui_hud_set_color(r, g, b, a)
    djui_hud_render_rect(x, y, width, height)
end

local function draw_border(x, y, width, height, r, g, b, a)
    draw_rect(x, y, width, 2, r, g, b, a)
    draw_rect(x, y + height - 2, width, 2, r, g, b, a)
    draw_rect(x, y, 2, height, r, g, b, a)
    draw_rect(x + width - 2, y, 2, height, r, g, b, a)
end

local function draw_heart(x, y, scale, alpha)
    local size = 5 * scale

    draw_rect(
        x - size * 1.2,
        y - size * 0.8,
        size,
        size,
        255,
        255,
        255,
        alpha
    )

    draw_rect(
        x + size * 0.2,
        y - size * 0.8,
        size,
        size,
        255,
        255,
        255,
        alpha
    )

    draw_rect(
        x - size * 0.8,
        y,
        size * 1.6,
        size,
        255,
        255,
        255,
        alpha
    )

    draw_rect(
        x - size * 0.4,
        y + size,
        size * 0.8,
        size,
        255,
        255,
        255,
        alpha
    )
end

local function draw_timing_line(x, y, width, alpha)
    draw_rect(
        x,
        y,
        width,
        2,
        255,
        255,
        255,
        alpha
    )

    local targetWidth = width * 0.12
    local targetX = x + (width - targetWidth) / 2

    draw_rect(
        targetX,
        y - 5,
        targetWidth,
        12,
        255,
        255,
        255,
        alpha
    )

    draw_rect(
        targetX + 3,
        y - 2,
        targetWidth - 6,
        6,
        0,
        0,
        0,
        alpha
    )
end

local function draw_heart_indicator(x, y, width, alpha)
    local heartX = x + (width * secondWindPosition)

    draw_heart(
        heartX,
        y - 12,
        0.9,
        alpha
    )
end

local function draw_hit_markers(x, y, alpha)
    local spacing = 22
    local totalWidth = spacing * 2
    local startX = x - totalWidth / 2

    for i = 1, SECOND_WIND_REQUIRED_HITS do
        local filled = i <= secondWindHits
        local markerX = startX + ((i - 1) * spacing)

        if filled then
            draw_rect(
                markerX,
                y,
                12,
                12,
                255,
                255,
                255,
                alpha
            )
        else
            draw_border(
                markerX,
                y,
                12,
                12,
                255,
                255,
                255,
                alpha * 0.55
            )
        end
    end
end

local function draw_second_wind_active(alpha)
    local screenWidth = djui_hud_get_screen_width()
    local screenHeight = djui_hud_get_screen_height()

    local panelWidth = math.min(430, screenWidth - 40)
    local panelHeight = 168

    local x = (screenWidth - panelWidth) / 2
    local y = screenHeight * 0.60

    draw_rect(
        x + 4,
        y + 5,
        panelWidth,
        panelHeight,
        0,
        0,
        0,
        alpha * 0.55
    )

    draw_rect(
        x,
        y,
        panelWidth,
        panelHeight,
        0,
        0,
        0,
        alpha * 0.92
    )

    draw_border(
        x,
        y,
        panelWidth,
        panelHeight,
        255,
        255,
        255,
        alpha
    )

    draw_text_centered(
        "SECOND WIND",
        y + 12,
        0.75,
        255,
        255,
        255,
        alpha
    )

    draw_text_centered(
        "HIT THE CENTER",
        y + 40,
        0.40,
        180,
        180,
        180,
        alpha
    )

    local lineWidth = panelWidth - 70
    local lineX = x + 35
    local lineY = y + 84

    draw_timing_line(
        lineX,
        lineY,
        lineWidth,
        alpha
    )

    draw_heart_indicator(
        lineX,
        lineY,
        lineWidth,
        alpha
    )

    draw_hit_markers(
        screenWidth / 2,
        y + 112,
        alpha
    )

    local attemptText =
        tostring(secondWindAttempts) ..
        " ATTEMPTS"

    draw_text_centered(
        attemptText,
        y + 136,
        0.36,
        160,
        160,
        160,
        alpha
    )
end

local function draw_second_wind_success(alpha)
    local screenWidth = djui_hud_get_screen_width()
    local screenHeight = djui_hud_get_screen_height()

    local panelWidth = math.min(390, screenWidth - 50)
    local panelHeight = 118

    local x = (screenWidth - panelWidth) / 2
    local y = screenHeight * 0.64

    draw_rect(
        x + 4,
        y + 5,
        panelWidth,
        panelHeight,
        0,
        0,
        0,
        alpha * 0.55
    )

    draw_rect(
        x,
        y,
        panelWidth,
        panelHeight,
        0,
        0,
        0,
        alpha * 0.94
    )

    draw_border(
        x,
        y,
        panelWidth,
        panelHeight,
        255,
        255,
        255,
        alpha
    )

    draw_text_centered(
        "SECOND WIND",
        y + 13,
        0.72,
        255,
        255,
        255,
        alpha
    )

    draw_text_centered(
        "YOU'RE BACK",
        y + 48,
        0.58,
        255,
        255,
        255,
        alpha
    )

    draw_hit_markers(
        screenWidth / 2,
        y + 82,
        alpha
    )
end

local function draw_second_wind_failed(alpha)
    local screenWidth = djui_hud_get_screen_width()
    local screenHeight = djui_hud_get_screen_height()

    local panelWidth = math.min(390, screenWidth - 50)
    local panelHeight = 118

    local x = (screenWidth - panelWidth) / 2
    local y = screenHeight * 0.64

    draw_rect(
        x + 4,
        y + 5,
        panelWidth,
        panelHeight,
        0,
        0,
        0,
        alpha * 0.55
    )

    draw_rect(
        x,
        y,
        panelWidth,
        panelHeight,
        0,
        0,
        0,
        alpha * 0.94
    )

    draw_border(
        x,
        y,
        panelWidth,
        panelHeight,
        255,
        255,
        255,
        alpha
    )

    draw_text_centered(
        "SECOND WIND",
        y + 13,
        0.72,
        255,
        255,
        255,
        alpha
    )

    draw_text_centered(
        "MISSED",
        y + 48,
        0.58,
        255,
        255,
        255,
        alpha
    )

    draw_text_centered(
        "NO SECOND CHANCE",
        y + 78,
        0.38,
        170,
        170,
        170,
        alpha
    )
end

local function render_second_wind()
    if secondWindState == SECOND_WIND_STATE_IDLE then
        return
    end

    djui_hud_set_resolution(RESOLUTION_DJUI)
    djui_hud_set_font(FONT_NORMAL)

    secondWindPulse =
        math.max(
            0,
            secondWindPulse - 1
        )

    if secondWindState == SECOND_WIND_STATE_ACTIVE then
        secondWindHudAlpha = clamp(
            secondWindHudAlpha + 24,
            0,
            255
        )

        draw_second_wind_active(
            secondWindHudAlpha
        )

        return
    end

    if secondWindState == SECOND_WIND_STATE_SUCCESS then
        draw_second_wind_success(255)
        return
    end

    if secondWindState == SECOND_WIND_STATE_FAILED then
        draw_second_wind_failed(255)
    end
end

local function on_test_button()
    if not network_is_server() then
        djui_chat_message_create(
            "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ Only the host can start the test."
        )

        return
    end

    secondWindTestRequested = true

    djui_chat_message_create(
        "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ Test enabled. Take damage or use /secondwind test."
    )
end

local function on_reset_button()
    reset_second_wind()

    secondWindCooldown = 0
    gPlayerSyncTable[0].secondWindAvailable = true
    gPlayerSyncTable[0].secondWindRecovered = false

    djui_chat_message_create(
        "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ Charge reset."
    )
end

local function on_enabled_changed(index, value)
    secondWindMenuEnabled = value

    if network_is_server() then
        gGlobalSyncTable.secondWindEnabled = value
    end

    if not value then
        reset_second_wind()
    end
end

local function on_difficulty_changed(index, value)
    secondWindMenuDifficulty = value

    if network_is_server() then
        gGlobalSyncTable.secondWindDifficulty = value
    end
end

local function on_chat_command(msg)
    msg = string.lower(msg or "")

    if msg == "test" then
        if not network_is_server() then
            djui_chat_message_create(
                "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ Only the host can start the test."
            )

            return true
        end

        local m = gMarioStates[0]

        if m ~= nil then
            secondWindSavedPosition = copy_position(m)
            secondWindSavedAngle = m.faceAngle.y
            secondWindTestRequested = false

            gPlayerSyncTable[0].secondWindAvailable = true

            start_second_wind(m)

            djui_chat_message_create(
                "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ Timing test started."
            )
        end

        return true
    end

    if msg == "reset" then
        reset_second_wind()

        secondWindCooldown = 0
        gPlayerSyncTable[0].secondWindAvailable = true
        gPlayerSyncTable[0].secondWindRecovered = false

        djui_chat_message_create(
            "\\#FFFFFF\\[Second Wind]\\#AAAAAA\\ Charge reset."
        )

        return true
    end

    djui_chat_message_create(
        "\\#FFFFFF\\Second Wind commands\\#AAAAAA\\"
    )

    djui_chat_message_create(
        "/secondwind test"
    )

    djui_chat_message_create(
        "/secondwind reset"
    )

    return true
end

local function update_test_request()
    if not secondWindTestRequested then
        return
    end

    if secondWindState ~= SECOND_WIND_STATE_IDLE then
        return
    end

    local m = gMarioStates[0]

    if m == nil then
        return
    end

    secondWindTestRequested = false

    gPlayerSyncTable[0].secondWindAvailable = true

    start_second_wind(m)
end

local function initialize_second_wind()
    gGlobalSyncTable.secondWindEnabled = true
    gGlobalSyncTable.secondWindDifficulty = 1

    gPlayerSyncTable[0].secondWindAvailable = true
    gPlayerSyncTable[0].secondWindRecovered = false

    reset_second_wind()
end

hook_event(
    HOOK_MARIO_UPDATE,
    mario_update
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
    update_test_request
)

hook_event(
    HOOK_ON_HUD_RENDER,
    render_second_wind
)

hook_chat_command(
    "secondwind",
    "[test|reset]",
    on_chat_command
)

hook_mod_menu_checkbox(
    "Enabled",
    true,
    on_enabled_changed
)

hook_mod_menu_slider(
    "Difficulty",
    1,
    1,
    3,
    on_difficulty_changed
)

hook_mod_menu_button(
    "Test Timing Challenge",
    on_test_button
)

hook_mod_menu_button(
    "Reset Second Wind",
    on_reset_button
)

initialize_second_wind()

print("[Second Wind] Created by CrypticTM")
print("[Second Wind] Work in progress.")
print("[Second Wind] Loaded.")