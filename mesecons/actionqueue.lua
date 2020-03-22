mesecon.queue.actions={} -- contains all ActionQueue actions

function mesecon.queue:add_function(name, func)
	mesecon.queue.funcs[name] = func
end

-- If add_action with twice the same overwritecheck and same position are called, the first one is overwritten
-- use overwritecheck nil to never overwrite, but just add the event to the queue
-- priority specifies the order actions are executed within one globalstep, highest first
-- should be between 0 and 1
function mesecon.queue:add_action(pos, func, params, time, overwritecheck, priority)
	-- Create Action Table:
	time = time or 0 -- time <= 0 --> execute, time > 0 --> wait time until execution
	priority = priority or 1
	local action = {	pos=mesecon.tablecopy(pos),
				func=func,
				params=mesecon.tablecopy(params or {}),
				time=time,
				owcheck=(overwritecheck and mesecon.tablecopy(overwritecheck)) or nil,
				priority=priority}

	local toremove = nil
	-- Otherwise, add the action to the queue
	if overwritecheck then -- check if old action has to be overwritten / removed:
		for i, ac in ipairs(mesecon.queue.actions) do
			if(vector.equals(pos, ac.pos)
			and mesecon.cmpAny(overwritecheck, ac.owcheck)) then
				toremove = i
				break
			end
		end
	end

	if (toremove ~= nil) then
		table.remove(mesecon.queue.actions, toremove)
	end

	table.insert(mesecon.queue.actions, action)
end

-- execute the stored functions on a globalstep
-- if however, the pos of a function is not loaded (get_node_or_nil == nil), do NOT execute the function
-- this makes sure that resuming mesecons circuits when restarting minetest works fine
-- However, even that does not work in some cases, that's why we delay the time the globalsteps
-- start to be execute by 5 seconds
local get_highest_priority = function (actions)
	local highestp = 2000000000
	local highesti
	for i, ac in ipairs(actions) do
		if ac.priority < highestp then
			highestp = ac.priority
			highesti = i
		end
	end

	return highesti
end

local m_time = 0
local resumetime = mesecon.setting("resumetime", 4)
minetest.register_globalstep(function (dtime)
	m_time = m_time + dtime
	-- don't even try if server has not been running for XY seconds; resumetime = time to wait
	-- after starting the server before processing the ActionQueue, don't set this too low
	if (m_time < resumetime) then return end
	local actions = mesecon.tablecopy(mesecon.queue.actions)
	local actions_now={}

	mesecon.queue.actions = {}
	local lowest_priority = 0;

	-- sort actions into two categories:
	-- those toexecute now (actions_now) and those to execute later (mesecon.queue.actions)
	for i, ac in ipairs(actions) do
		if ac.time > 0 then
			ac.time = ac.time - dtime -- executed later
			table.insert(mesecon.queue.actions, ac)
		else
			if actions_now[ac.priority] == nil then
				actions_now[ac.priority] = {}
			end
			table.insert(actions_now[ac.priority], ac)
			if ac.priority > lowest_priority then
				lowest_priority = ac.priority
			end
		end
	end

	local end_at = minetest.get_us_time() + 90000
	local p = 0
	-- execute highest priorities first, until all are executed
	while p < lowest_priority and minetest.get_us_time() < end_at do  
		p = p+1
		if actions_now[p] ~= nil then
			while #(actions_now[p]) > 0 and minetest.get_us_time() < end_at do
				--local hp = get_highest_priority(actions_now)
				mesecon.queue:execute(actions_now[p][#(actions_now[p])])
				actions_now[p][#(actions_now[p])] = nil
			end
		end
	end
	
	-- Actions which weren't performed in time will be executed later.
	for i, p in ipairs(actions_now) do
		for j, ac in ipairs(p) do
			table.insert(mesecon.queue.actions, ac)
		end
	end
end)

function mesecon.queue:execute(action)
	-- ignore if action queue function name doesn't exist,
	-- (e.g. in case the action queue savegame was written by an old mesecons version)
	if mesecon.queue.funcs[action.func] then
		mesecon.queue.funcs[action.func](action.pos, unpack(action.params))
	end
end


-- Store and read the ActionQueue to / from a file
-- so that upcoming actions are remembered when the game
-- is restarted
mesecon.queue.actions = mesecon.file2table("mesecon_actionqueue")

minetest.register_on_shutdown(function()
	mesecon.table2file("mesecon_actionqueue", mesecon.queue.actions)
end)
