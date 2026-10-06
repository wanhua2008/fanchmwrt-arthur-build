-- luci-app-arthur-nas: 京东云亚瑟 NAS 共享管理页面
module("luci.controller.arthur_nas", package.seeall)

local SETUP = "/usr/lib/arthur-nas/arthur-nas-setup.sh"
local LOG = "/tmp/arthur-nas-setup.log"

function index()
	entry({"admin", "services", "arthur_nas"}, template("arthur_nas/page"), _("亚瑟NAS共享"), 80)
	entry({"admin", "services", "arthur_nas", "status"}, call("action_status"))
	entry({"admin", "services", "arthur_nas", "setup"}, call("action_setup"))
	entry({"admin", "services", "arthur_nas", "log"}, call("action_log"))
	entry({"admin", "services", "arthur_nas", "restart"}, call("action_restart"))
end

local function out_json(t)
	luci.http.prepare_content("application/json")
	luci.http.write_json(t)
end

function action_status()
	local o = luci.sys.exec(
		"[ -b /dev/mmcblk0p27 ] && echo P1=1\n" ..
		"mount 2>/dev/null | grep -q ' on /mnt/mmcblk0p27 ' && echo M1=1\n" ..
		"ps 2>/dev/null | grep -q '[s]mbd' && echo S1=1\n" ..
		"ps 2>/dev/null | grep -q '[a]rthur-nas-setup' && echo J1=1\n" ..
		"df -m /mnt/mmcblk0p27 2>/dev/null | awk 'NR==2{printf \"T=%d A=%d\\n\", $2, $4}'\n" ..
		"[ -f /usr/lib/arthur-nas/usb-automount.sh ] && echo U0=1\n" ..
		"ps 2>/dev/null | grep -q '[g]ecoosac' && echo G1=1\n"
	)
	local st = { part = false, mount = false, smb = false, job = false,
	             size = 0, avail = 0, usbauto = false, gecoos = false, usb = {} }
	local line
	for line in o:gmatch("[^\r\n]+") do
		if line:match("P1=1") then st.part = true end
		if line:match("M1=1") then st.mount = true end
		if line:match("S1=1") then st.smb = true end
		if line:match("J1=1") then st.job = true end
		if line:match("U0=1") then st.usbauto = true end
		if line:match("G1=1") then st.gecoos = true end
		local t, a = line:match("T=(%d+) A=(%d+)")
		if t and a then
			st.size = tonumber(t)
			st.avail = tonumber(a)
		end
	end

	-- 扫描 USB/SD 设备
	local ls = luci.sys.exec(
		"for d in /dev/sd?1 /dev/sd?; do [ -b \"$d\" ] || continue; " ..
		"n=${d#/dev/}; m=$(mount 2>/dev/null | grep \"^$d \" | awk '{print $3}'); " ..
		"echo \"$n|$m\"; done\n" ..
		"for m in /mnt/sd*; do [ -d \"$m\" ] || continue; " ..
		"sz=$(df -m \"$m\" 2>/dev/null | awk 'NR==2{print $2}'); " ..
		"av=$(df -m \"$m\" 2>/dev/null | awk 'NR==2{print $4}'); " ..
		"echo \"MNT|$m|$sz|$av\"; done\n"
	)
	local dev
	for dev in ls:gmatch("[^\r\n]+") do
		local n, m = dev:match("^([^|]+)|(.*)$")
		if n and n ~= "MNT" and m and m ~= "" then
			table.insert(st.usb, { name = n, mnt = m })
		end
	end

	out_json(st)
end

function action_setup()
	os.execute("setsid sh " .. SETUP .. " > " .. LOG .. " 2>&1 < /dev/null &")
	out_json({ ok = true })
end

function action_log()
	local f = io.open(LOG, "r")
	local txt = ""
	if f then
		txt = f:read("*a") or ""
		f:close()
	end
	local running = luci.sys.exec("ps 2>/dev/null | grep -q '[a]rthur-nas-setup' && echo yes || echo no")
	out_json({ log = txt, running = (running:match("yes") ~= nil) })
end

function action_restart()
	luci.sys.exec("/etc/init.d/samba4 restart >/dev/null 2>&1")
	out_json({ ok = true })
end
