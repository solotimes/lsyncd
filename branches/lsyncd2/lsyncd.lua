------------------------------------------------------------------------------
-- lsyncd.lua   Live (Mirror) Syncing Demon
--
-- License: GPLv2 (see COPYING) or any later version
--
-- Authors: Axel Kittenberger <axkibe@gmail.com>
--
-- This is the "runner" part of lsyncd. It containts all its high-level logic.
-- It works closely together with the lsyncd core in lsyncd.c. This means it
-- cannot be runned directly from the standard lua interpreter.
------------------------------------------------------------------------------

----
-- A security measurement.
-- Core will exit if version ids mismatch.
if lsyncd_version ~= nil then
	print "You cannot use the lsyncd runner as configuration file!"
	os.exit(-1)
end
lsyncd_version = "2.0b1"

----
-- Table of all directories to watch.
origins = {}

----
-- all targets
targets = {}

-----
-- all watches
watches = {}

----
-- Adds watches for a directory including all subdirectories.
--
-- @param sdir
-- @param target
--
local function attend_dir(origin, path, target)
	-- actual dir = origin + path 
	local op = origin .. path
	-- register watch and receive watch descriptor
	local wd = lsyncd.add_watch(op);
	if wd < 0 then
		-- failed adding the watch
		-- TODO die?
		return
	end

	if watches[wd] ~= nil then
		-- this directory is already watched, add the target
		local watch = watches[wd]
		table.insert(watch.attends, { origin = origin, path = path, target = target })
	else
		-- new watch
		local watch = {wd = wd, attends = { origin = origin, path = path, target = target } }
		watches[wd] = watch
	end

	-- register all subdirectories 
	local subd = lsyncd.sub_dirs(op);
	local i, o
	for i, v in ipairs(subd) do
		attend_dir(origin, path .. v .. "/", target)
	end
end

----
-- Called from core on init or restart after user configuration.
-- 
function lsyncd_initialize()
	local i, o
	for i, o in ipairs(origins) do
		-- resolves source to be an absolute path
		local src = lsyncd.real_dir(o.source)
		if src == nil then
			print("Cannot resovle source path: ", src)
			lsyncd.terminate() -- ERRNO
		end
		o.source = src

		-- appends the target on target lists
		local target = { path = o.targetpath }
		table.insert(targets, target)
		o.target = target

		-- and add the dir watch inclusively all subdirs
		attend_dir(o.source, "", target)
	end
end

----
-- Called by core to determine soonest alarm.
--
-- @param  now   ... the current time representation.
--
-- @return two variables.
--         number -1 means ... alarm is in the past.
--                 0 means ... no alarm, core can in untimed sleep
--                 1 means ... alarm time specified.
--         times           ... the alarm time (only read if number is 1)
function lsyncd_get_alarm()
	return 0, 0
end

-----
-- TODO
--
local event_names = {
	[ATTRIB] = "Attrib",
	[MODIFY] = "Modify",
	[CREATE] = "Create",
	[DELETE] = "Delete",
	[MOVE  ] = "Move",
}

-----
-- Called by core on inotify event
--
-- @param etype     enum (ATTRIB, MODIFY, CREATE, DELETE, MOVE)
-- @param wd        watch descriptor (matches lsyncd.add_watch())
-- @param filename  string filename without path
-- @param filename2 
--
function lsyncd_event(etype, wd, filename, filename2)
	if filename2 == nil then
		print("got event " .. event_names[etype] .. " of " .. filename) 
	else 
		print("got event " .. event_names[etype] .. " of " .. filename .. " to " .. filename2) 
	end
end

------------------------------------------------------------------------------
-- lsyncd user interface
------------------------------------------------------------------------------

----
-- Adds one directory to be watched.
--
function add(source_dir, target_path)
	local o = { source = source_dir, targetpath = target_path }
	table.insert(origins, o)
	return o
end

----
-- Called by core when an overflow happened.
function default_overflow()
	print("--- OVERFLOW on inotify event queue ---")
	lsyncd.terminate(-1) -- TODO reset instead.

end
overflow = default_overflow

-----
-- Called by core on event
--
--
-- @return the pid of a spawned child process or 0 if no spawn.
function default_event()
	print("got an event")
	return 0
end

-----
-- Called by core after initialization.
--
-- Default function will start an simultanous action for every 
-- source -> destination pair. And waits for these processes to finish
--
-- The user can override this function by specifing his/her own
-- "startup". (and yet may still call default startup)
--
function default_startup()
	print("--- startup ---")
	local pids = { }
	for i, o in ipairs(origins) do
		startup_action(o.source, o.targetpath)
		table.insert(pids, pid)
	end
	lsyncd.wait_pids(pids, "startup_collector")
	print("--- Entering normal operation with " .. #watches .. " monitored directories ---")
end
startup = default_startup


-----
-- Called by the core for every child process that 
-- finished in startup phase
--
-- Parameters are pid and exitcode of child process
--
-- Can return either a new pid if one other child process 
-- has been spawned as replacement (e.g. retry) or 0 if
-- finished/ok.
--
function default_startup_collector(pid, exitcode)
	if exitcode ~= 0 then
		print("Startup process", pid, " failed")
		lsyncd.terminate(-1) -- ERRNO
	end
	return 0
end
startup_collector = default_startup_collector

----
-- other functions the user might want to use
exec = lsyncd.exec

