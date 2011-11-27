
-- Use LuaRocks if available
pcall(require, "luarocks.require");

-- Load LuaSec if available
pcall(require, "ssl");

local server = require "net.server";
local events = require "util.events";
local logger = require "util.logger";

module("verse", package.seeall);
local verse = _M;
_M.server = server;

local stream = {};
stream.__index = stream;
stream_mt = stream;

verse.plugins = {};

function verse.new(logger, base)
	local t = setmetatable(base or {}, stream);
	t.id = tostring(t):match("%x*$");
	t.logger = logger or verse.new_logger("stream"..t.id);
	t.events = events.new();
	t.plugins = {};
	return t;
end

verse.add_task = require "util.timer".add_task;

verse.logger = logger.init; -- COMPAT: Deprecated
verse.new_logger = logger.init;
verse.log = verse.logger("verse");

function verse.set_log_handler(log_handler, levels)
	levels = levels or { "debug", "info", "warn", "error" };
	logger.reset();
	for i, level in ipairs(levels) do
		logger.add_level_sink(level, log_handler);
	end
end

local function error_handler(err)
	verse.log("error", "Error: %s", err);
	verse.log("error", "Traceback: %s", debug.traceback());
end

function verse.set_error_handler(new_error_handler)
	error_handler = new_error_handler;
end

function verse.loop()
	return xpcall(server.loop, error_handler);
end

function verse.step()
	return xpcall(server.step, error_handler);
end

function verse.quit()
	return server.setquitting(true);
end

function stream:connect(connect_host, connect_port)
	connect_host = connect_host or "localhost";
	connect_port = tonumber(connect_port) or 5222;
	
	-- Create and initiate connection
	local conn = socket.tcp()
	conn:settimeout(0);
	local success, err = conn:connect(connect_host, connect_port);
	
	if not success and err ~= "timeout" then
		self:warn("connect() to %s:%d failed: %s", connect_host, connect_port, err);
		return self:event("disconnected", { reason = err }) or false, err;
	end

	local conn = server.wrapclient(conn, connect_host, connect_port, new_listener(self), "*a");
	if not conn then
		self:warn("connection initialisation failed: %s", err);
		return self:event("disconnected", { reason = err }) or false, err;
	end
	
	self.conn = conn;
	self.send = function (stream, data)
		self:event("outgoing", data);
		data = tostring(data);
		self:event("outgoing-raw", data);
		return conn:write(data);
	end;
	return true;
end

function stream:close()
	if not self.conn then 
		verse.log("error", "Attempt to close disconnected connection - possibly a bug");
		return;
	end
	local on_disconnect = self.conn.disconnect();
	self.conn:close();
	on_disconnect(conn, reason);
end

-- Logging functions
function stream:debug(...)
	return self.logger("debug", ...);
end

function stream:warn(...)
	return self.logger("warn", ...);
end

function stream:error(...)
	return self.logger("error", ...);
end

-- Event handling
function stream:event(name, ...)
	self:debug("Firing event: "..tostring(name));
	return self.events.fire_event(name, ...);
end

function stream:hook(name, ...)
	return self.events.add_handler(name, ...);
end

function stream:unhook(name, handler)
	return self.events.remove_handler(name, handler);
end

function verse.eventable(object)
        object.events = events.new();
        object.hook, object.unhook = stream.hook, stream.unhook;
        local fire_event = object.events.fire_event;
        function object:event(name, ...)
                return fire_event(name, ...);
        end
        return object;
end

function stream:add_plugin(name)
	if self.plugins[name] then return true; end
	if require("verse.plugins."..name) then
		local ok, err = verse.plugins[name](self);
		if ok ~= false then
			self:debug("Loaded %s plugin", name);
			self.plugins[name] = true;
		else
			self:warn("Failed to load %s plugin: %s", name, err);
		end
	end
	return self;
end

-- Listener factory
function new_listener(stream)
	local conn_listener = {};
	
	function conn_listener.onconnect(conn)
		stream.connected = true;
		stream:event("connected");
	end
	
	function conn_listener.onincoming(conn, data)
		stream:event("incoming-raw", data);
	end
	
	function conn_listener.ondisconnect(conn, err)
		stream.connected = false;
		stream:event("disconnected", { reason = err });
	end

	function conn_listener.ondrain(conn)
		stream:event("drained");
	end
	
	function conn_listener.onstatus(conn, new_status)
		stream:event("status", new_status);
	end
	
	return conn_listener;
end


local log = require "util.logger".init("verse");

return verse;
