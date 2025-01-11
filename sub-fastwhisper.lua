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
    language = "",
    -- Number of cpu threads to use
    -- Default value is 0 will auto-detect but max 4 threads
    threads = "0",
    -- Specify output path, supports absolute and relative paths
    -- Special value: "source" saves the subtitle file to the directory 
    -- where the video file is located
    output_path = "source",
}

options.read_options(o)
------------------------

local fast_whisper_path = mp.command_native({ "expand-path", o.fast_whisper_path })
local output_path = mp.command_native({ "expand-path", o.output_path })

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

    local arg = {
        fast_whisper_path,
        path,
        "--model", o.model,
        "--device", o.device,
        "--threads", o.threads,
        "--output_dir", output_path,
    }

    if o.language ~= "" then
        table.insert(arg, "--language")
        table.insert(arg, o.language)
    end

    local screenx, screeny, aspect = mp.get_osd_size()
    mp.set_osd_ass(screenx, screeny, "{\\an9}● ")
    mp.osd_message("AI subtitle generation in progress", 9)
    msg.info("AI subtitle generation in progress")
    local res = mp.command_native({ name = "subprocess", capture_stdout = true, playback_only = false, args = arg })
    mp.set_osd_ass(screenx, screeny, "")
    if res.status == 0 then
        if file_exists(subtitles_file) then
            mp.osd_message("AI subtitles successfully generated", 5)
            msg.info("AI subtitles successfully generated")
            mp.commandv("sub-add", subtitles_file)
        end
    else
        mp.osd_message("AI subtitle generation failed, check console for more info.")
        msg.info("AI subtitle generation failed")
    end
end

mp.register_script_message("sub-fastwhisper", fastwhisper)