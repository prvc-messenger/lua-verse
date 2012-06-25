-- This implements XEP-0313: Message Archive Management
-- http://xmpp.org/extensions/xep-0313.html
-- (ie not XEP-0136)

local verse = require "verse";
local st = require "util.stanza";
local xmlns_mam = "urn:xmpp:mam:tmp"
local xmlns_forward = "urn:xmpp:forward:0";
local xmlns_delay = "urn:xmpp:delay";
local uuid = require "util.uuid".generate;
local parse_datetime = require "util.datetime".parse;
local datetime = require "util.datetime".datetime;
local rsm = require "util.rsm";
local tonumber = tonumber;
local NULL = {};

function verse.plugins.archive(stream)
	function stream:query_archive(where, query_params, callback)
		local queryid = uuid();
		local query_st = st.iq{ type="get", to = where }
			:tag("query", { xmlns = xmlns_mam, queryid = queryid });

		local qwith = query_params["with"];
		if qwith then
			query_st:tag("with"):text(qwith):up();
		end

		local qstart, qend = tonumber(query_params["start"]), tonumber(query_params["end"]);
		if qstart then
			query_st:tag("start"):text(datetime(qstart)):up();
		end
		if qend then
			query_st:tag("end"):text(datetime(qend)):up();
		end

		query_st:add_child(rsm.generate(query_params));

		local results = {};
		local function handle_archived_message(message)
			local result_tag = message:get_child("result", xmlns_mam);
			if result_tag and result_tag.attr.queryid == queryid then
				local forwarded = message:get_child("forwarded", xmlns_forward);

				local id = result_tag.attr.id;
				local delay = forwarded:get_child("delay", xmlns_delay);
				local stamp = delay and parse_datetime(delay.attr.stamp) or nil;

				local message = forwarded:get_child("message", "jabber:client")

				results[#results+1] = { id = id, stamp = stamp, message = message };
				return true
			end
		end

		self:hook("message", handle_archived_message, 1);
		self:send_iq(query_st, function(reply)
			self:unhook("message", handle_archived_message);
			local rset = reply.tags[1] and rsm.get(reply.tags[1]);
			for k,v in pairs(rset or NULL) do results[k]=v; end
			callback(reply.attr.type == "result" and #results, results);
			return true
		end);
	end

	local default_attrs = {
		always = true, [true] = "always",
		never = false, [false] = "never",
		roster = "roster",
	}

	local function prefs_decode(stanza) -- from XML
		local prefs = {};
		local default = stanza.attr.default;

		if default then
			prefs[false] = default_attrs[default];
		end

		local always = stanza:get_child("always");
		if always then
			for rule in always:childtags("jid") do
				local jid = rule:get_text();
				prefs[jid] = true;
			end
		end

		local never = stanza:get_child("never");
		if never then
			for rule in never:childtags("jid") do
				local jid = rule:get_text();
				prefs[jid] = false;
			end
		end
		return prefs;
	end

	local function prefs_encode(prefs) -- into XML
		local default
		default, prefs[false] = prefs[false], nil;
		if default ~= nil then
			default = default_attrs[default];
		end
		local reply = st.stanza("prefs", { xmlns = xmlns_mam, default = default })
		local always = st.stanza("always");
		local never = st.stanza("never");
		for k,v in pairs(prefs) do
			(v and always or never):tag("jid"):text(k):up();
		end
		return reply:add_child(always):add_child(never);
	end

	function stream:archive_prefs_get(callback)
		self:send_iq(st.iq{ type="get" }:tag("prefs", { xmlns = xmlns_mam }),
		function(result)
			if result and result.attr.type == "result" and result.tags[1] then
				local prefs = prefs_decode(result.tags[1]);
				callback(prefs, result);
			else
				callback(nil, result);
			end
		end);
	end

	function stream:archive_prefs_set(prefs, callback)
		self:send_iq(st.iq{ type="set" }:add_child(prefs_encode(prefs)), callback);
	end
end
