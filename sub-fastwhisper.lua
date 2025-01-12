--[[
    * sub-fastwhisper.lua
    *
    * AUTHORS: dyphire
    * License: MIT
    * link: https://github.com/dyphire/mpv-sub-fastwhisper
]]

local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require "mp.options"

---- Script Options ----
local o = {
    -- Path to the whisper-faster executable, you can download it from here:
    -- https://github.com/Purfview/whisper-standalone-win
    -- Supports absolute and relative paths
    fast_whisper_path = "whisper-faster",
    -- Model to use, available models are: base, small，medium, large, turbo
    model = "base",
    -- Device to use, available devices are: cpu, cuda
    device = "cpu",
    -- Specify the language of transcription
    -- Leave it blank and it will be automatically detected
    language = "",
    -- Number of cpu threads to use
    -- Default value is 0 will auto-detect but max 4 threads
    threads = "0",
    -- Specify output path, supports absolute and relative paths
    -- Special value: "source" saves the subtitle file to the directory 
    -- where the video file is located
    output_path = "source",
    -- Specify how many subtitles are generated before updating
    -- to avoid frequent flickering of subtitles
    update_interval = 20,
}

options.read_options(o)
------------------------

local fast_whisper_path = mp.command_native({ "expand-path", o.fast_whisper_path })
local output_path = mp.command_native({ "expand-path", o.output_path })

local is_windows = package.config:sub(1, 1) == "\\"

local function is_protocol(path)
    return type(path) == 'string' and (path:find('^%a[%w.+-]-://') ~= nil or path:find('^%a[%w.+-]-:%?') ~= nil)
end

local function file_exists(path)
    if path then
        local meta = utils.file_info(path)
        return meta and meta.is_file
    end
    return false
end

local function normalize(path)
    if normalize_path ~= nil then
        if normalize_path then
            path = mp.command_native({"normalize-path", path})
        else
            local directory = mp.get_property("working-directory", "")
            path = utils.join_path(directory, path:gsub('^%.[\\/]',''))
            if is_windows then path = path:gsub("\\", "/") end
        end
        return path
    end

    normalize_path = false

    local commands = mp.get_property_native("command-list", {})
    for _, command in ipairs(commands) do
        if command.name == "normalize-path" then
            normalize_path = true
            break
        end
    end
    return normalize(path)
end

local function format_time(time_str)
    local h, m, s, ms = nil, nil, nil, nil
    if time_str:match("%d+:%d+:%d+%.%d+") then
        h, m, s, ms = time_str:match("(%d+):(%d+):(%d+)%.(%d+)")
    else
        m, s, ms = time_str:match("(%d+):(%d+)%.(%d+)")
    end

    if not h then h = 0 end

    return string.format("%02d:%02d:%02d,%03d", h, m, s, ms)
end

local function check_sub()
    local tracks = mp.get_property_native("track-list")
    local fname = mp.get_property("filename/no-ext")
    local sub_file = fname .. ".srt"
    for _, track in ipairs(tracks) do
        if track["type"] == "sub" and track["title"] == sub_file then
            return true, track["id"]
        end
    end
    return false, nil
end

local function append_sub(sub_file)
    local sub, id = check_sub()
    if not sub then
        mp.commandv('sub-add', sub_file)
    else
        mp.commandv('sub-reload', id)
    end
end

local function fastwhisper()
    local path = mp.get_property("path")
    local fname = mp.get_property("filename/no-ext")
    if not path or is_protocol(path) then return end
    if path then
        path = normalize(path)
        dir = utils.split_path(path)
    end

    if output_path ~= "source" then
        subtitles_file = utils.join_path(output_path, fname .. ".srt")
    else
        subtitles_file = utils.join_path(dir, fname .. ".srt")
    end

    if file_exists(subtitles_file) then return end

    local screenx, screeny, aspect = mp.get_osd_size()
    mp.set_osd_ass(screenx, screeny, "{\\an9}● ")
    mp.osd_message("AI subtitle generation in progress", 9)
    msg.info("AI subtitle generation in progress")
    local file = io.open(subtitles_file, "w")
    local command = string.format('%s "%s" --beep_off --model %s --device %s --output_dir %s',
    fast_whisper_path, path, o.model, o.device, output_path)

    if o.language ~= "" then
        command = command .. " --language " .. o.language
    end

    if file then
        file:setvbuf("no")

        local handle = io.popen(command .. " 2>&1")
        if handle then
            local subtitle_count = 1
            local append_subtitle_count = 1
            local subtitles_written = false
            while true do
                local line = handle:read("*line")
                if not line then break end 
                local text_pattern = "%[([%d+:]?%d+:%d+%.%d+)%D+([%d+:]?%d+:%d+%.%d+)%]%s*(.*)"
                local start_time_srt, end_time_srt, subtitle_text = line:match(text_pattern)
                if start_time_srt and end_time_srt and subtitle_text then
                    local start_time = format_time(start_time_srt)
                    local end_time = format_time(end_time_srt)

                    file:write(subtitle_count .. "\n")
                    file:write(start_time .. " --> " .. end_time.. "\n")
                    file:write(subtitle_text .. "\n\n")

                    subtitle_count = subtitle_count + 1
                    subtitles_written = true
                end
                if subtitle_count % o.update_interval == 1 and subtitles_written and file_exists(subtitles_file) then
                    if append_subtitle_count == 1 then
                        mp.osd_message("AI subtitles are loaded and updated in real time", 5)
                        msg.info("AI subtitles are loaded and updated in real time")
                    end
                    append_sub(subtitles_file)
                    subtitles_written = false
                    append_subtitle_count = append_subtitle_count + 1
                end
            end
            handle:close()
            mp.set_osd_ass(screenx, screeny, "")
        end
        file:close()
    end

    if file_exists(subtitles_file) then
        local file = io.open(subtitles_file, "r")
        if file then
            local content = file:read("*all")
            file:close()

            if content == "" then
                os.remove(subtitles_file)
            else
                mp.osd_message("AI subtitles successfully generated", 5)
                msg.info("AI subtitles successfully generated")
                append_sub(subtitles_file)
            end
        end
    end
end

mp.register_script_message("sub-fastwhisper", fastwhisper)
