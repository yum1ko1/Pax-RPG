# Генерирует Lua-скрипт сборки проекта в DaVinci Resolve (бесплатная версия: Workspace > Scripts > Utility).
import os, sys, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edl import *
import overlays

APPDATA = os.environ.get("APPDATA", "")
SCRIPTS = os.path.join(APPDATA, r"Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility")
LUTDIRS = [os.path.join(APPDATA, r"Blackmagic Design\DaVinci Resolve\Support\LUT\PaxIntro"),
           r"C:\ProgramData\Blackmagic Design\DaVinci Resolve\Support\LUT\PaxIntro"]
LOG = os.path.join(ROOT, "tools", "resolve_log.txt")


def L(s):
    return "[[" + s + "]]"


def main():
    luts = {}
    for look in sorted({c[6] for c in CLIPS}):
        src = os.path.join(LUTS, f"PaxIntro_{look}.cube")
        cands = []
        for d in LUTDIRS:
            try:
                os.makedirs(d, exist_ok=True)
                shutil.copy(src, d)
                cands.append(os.path.join(d, os.path.basename(src)))
            except Exception as e:
                print("lut copy skip", d, e)
        cands += ["PaxIntro/" + os.path.basename(src), src]
        luts[look] = cands
    o = []
    o.append("-- Pax RPG: «Битва при Расколе» — сборка проекта и рендер. Сгенерировано gen_lua.py")
    o.append(f"local LOGF = {L(LOG)}")
    o.append('local function log(...) local t = {...} for i = 1, #t do t[i] = tostring(t[i]) end local s = table.concat(t, " ") print("PAX " .. s) local f = io.open(LOGF, "a") if f then f:write(os.date("%H:%M:%S ") .. s .. "\\n") f:close() end end')
    o.append("local LUTS = {")
    for k, v in luts.items():
        o.append(f"  {k} = {{" + ", ".join(L(x) for x in v) + "},")
    o.append("}")
    o.append("local V = {  -- дорожка, файл, кадр на таймлайне, кадров, лук, имя")
    for c in CLIPS:
        o.append(f"  {{1, {L(os.path.join(PLATES, c[0] + '.mov'))}, {c[5]}, {c[3]}, \"{c[6]}\", \"{c[0]}\"}},")
    o.append(f"  {{2, {L(os.path.join(OV, 'frame_239.mov'))}, 0, {TOTAL}, nil, \"FRAME 2.39\"}},")
    for ti, lang in ((3, "ru"), (4, "en")):
        for k, (who, a, b, text) in enumerate(overlays.SUBS[lang]):
            n = int(round((b - a) * FPS))
            o.append(f"  {{{ti}, {L(os.path.join(OV, f'sub_{lang}_{k + 1:02d}.mov'))}, {int(round(a * FPS))}, {n}, nil, \"sub {lang} {k + 1}\"}},")
        o.append(f"  {{{ti}, {L(os.path.join(OV, f'card_open_{lang}.mov'))}, 24, 108, nil, \"card open {lang}\"}},")
        o.append(f"  {{{ti}, {L(os.path.join(OV, f'card_end_{lang}.mov'))}, 1243, 94, nil, \"card end {lang}\"}},")
    o.append("}")
    o.append("local A = {")
    for i, n in enumerate(("A_master", "A_music", "A_voice", "A_sfx", "A_amb", "A_impacts")):
        o.append(f"  {{{i + 1}, {L(os.path.join(AUDIO, n + '.wav'))}, \"{n[2:].upper()}\"}},")
    o.append("}")
    marks = [(6.95, "Red", "Врата / луч"), (12.45, "Red", "Небо трескается"), (15.08, "Blue", "Бой"),
             (22.25, "Purple", "Диалог сестёр"), (27.09, "Red", "Посох против косы"), (34.10, "Red", "Взрыв маны"),
             (38.75, "Red", "Оружие падает"), (42.10, "Yellow", "Рождается Око"), (45.65, "Red", "Удар клинков"),
             (46.35, "Purple", "Вознесись"), (51.80, "Yellow", "Титр")]
    o.append("local MARKS = {")
    for t, col, name in marks:
        o.append(f"  {{{int(round(t * FPS))}, \"{col}\", \"{name}\"}},")
    o.append("}")
    o.append(f"local RENDER_DIR = {L(RENDER)}")
    o.append(BODY)
    os.makedirs(SCRIPTS, exist_ok=True)
    out = os.path.join(SCRIPTS, "PaxIntro_Build.lua")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(o))
    print("lua", out)


BODY = r'''
local resolve = resolve or Resolve()
local pm = resolve:GetProjectManager()
log("=== build start", resolve:GetVersionString())
local name = "PaxRPG_Intro_BitvaPriRaskole"
local proj = pm:CreateProject(name)
local k = 2
while not proj and k < 60 do proj = pm:CreateProject(name .. "_v" .. k) if proj then name = name .. "_v" .. k end k = k + 1 end
if not proj then log("ERROR no project") return end
log("project", name)
for kk, v in pairs({timelineFrameRate = "24", timelinePlaybackFrameRate = "24", timelineResolutionWidth = "1920",
                     timelineResolutionHeight = "1080", colorScienceMode = "davinciYRGB"}) do
  log("setting", kk, tostring(proj:SetSetting(kk, v)))
end
local mp = proj:GetMediaPool()
local root = mp:GetRootFolder()
local bins = {p = mp:AddSubFolder(root, "01 PLATES (VFX)"), o = mp:AddSubFolder(root, "02 FRAME + TITLES"), a = mp:AddSubFolder(root, "03 AUDIO")}
local items = {}
local function imp(path, bin)
  if items[path] then return items[path] end
  mp:SetCurrentFolder(bin)
  local r = mp:ImportMedia({path})
  if r and r[1] then items[path] = r[1] else log("IMPORT FAILED", path) end
  return items[path]
end
for _, c in ipairs(V) do imp(c[2], c[1] == 1 and bins.p or bins.o) end
for _, a in ipairs(A) do imp(a[2], bins.a) end
log("imported")
mp:SetCurrentFolder(root)
local tl = mp:CreateEmptyTimeline("Bitva_pri_Raskole")
proj:SetCurrentTimeline(tl)
while tl:GetTrackCount("video") < 4 do tl:AddTrack("video") end
while tl:GetTrackCount("audio") < 6 do tl:AddTrack("audio", "stereo") end
local vn = {"V1 PLATES", "V2 FRAME 2.39", "V3 TITLES RU", "V4 TITLES EN"}
for i = 1, 4 do tl:SetTrackName("video", i, vn[i]) end
for _, a in ipairs(A) do tl:SetTrackName("audio", a[1], a[3]) end
local T0 = tl:GetStartFrame()
local okv, fail = 0, 0
for _, c in ipairs(V) do
  local it = items[c[2]]
  if it then
    local r = mp:AppendToTimeline({{mediaPoolItem = it, startFrame = 0, endFrame = c[4] - 1, trackIndex = c[1], recordFrame = T0 + c[3], mediaType = 1}})
    local ti = r and r[1]
    if ti then
      okv = okv + 1
      if c[5] then
        local done = false
        local g = ti.GetNodeGraph and ti:GetNodeGraph() or nil
        for _, l in ipairs(LUTS[c[5]]) do
          if not done then
            if g and g:SetLUT(1, l) then done = true elseif ti.SetLUT and ti:SetLUT(1, l) then done = true end
            if done then log("lut", c[6], l) end
          end
        end
        if not done then log("LUT NOT APPLIED", c[6]) end
        ti:SetClipColor(({dawn = "Yellow", rift = "Pink", war = "Orange", iru = "Purple", selune = "Navy", blast = "Apricot", menu = "Teal"})[c[5]] or "Blue")
      end
    else
      fail = fail + 1
      log("APPEND FAILED", c[6])
    end
  end
end
for _, a in ipairs(A) do
  local it = items[a[2]]
  if it then
    local r = mp:AppendToTimeline({{mediaPoolItem = it, trackIndex = a[1], recordFrame = T0, mediaType = 2}})
    if not (r and r[1]) then log("AUDIO APPEND FAILED", a[3]) end
  end
end
tl:SetTrackEnable("video", 4, false)
for i = 2, 6 do tl:SetTrackEnable("audio", i, false) end
for _, m in ipairs(MARKS) do tl:AddMarker(m[1], m[2], m[3], "", 1) end
log("placed video", okv, "failed", fail)
pm:SaveProject()
-- рендер
resolve:OpenPage("deliver")
proj:DeleteAllRenderJobs()
local fmt, codec = "mp4", nil
local codecs = proj:GetRenderCodecs(fmt) or {}
for desc, key in pairs(codecs) do
  if not codec and (tostring(key):find("264") or tostring(desc):find("264")) then codec = key end
end
log("codec", tostring(codec), tostring(proj:SetCurrentRenderFormatAndCodec(fmt, codec or "H264")))
proj:SetRenderSettings({SelectAllFrames = true, TargetDir = RENDER_DIR, CustomName = "Pax_RPG_Intro_Resolve",
  ExportVideo = true, ExportAudio = true, FormatWidth = 1920, FormatHeight = 1080, FrameRate = 24, VideoQuality = 0,
  AudioCodec = "aac", AudioBitDepth = 24, AudioSampleRate = 48000})
local job = proj:AddRenderJob()
log("job", tostring(job))
proj:StartRendering({job})
local t = 0
while proj:IsRenderingInProgress() and t < 3600 do
  if t % 10 == 0 then local st = proj:GetRenderJobStatus(job) log("render", st and st.CompletionPercentage, st and st.JobStatus) end
  bmd.wait(1) t = t + 1
end
local st = proj:GetRenderJobStatus(job)
log("render done", st and st.JobStatus, st and st.Error)
pm:SaveProject()
resolve:OpenPage("edit")
log("=== DONE")
'''

if __name__ == "__main__":
    main()
