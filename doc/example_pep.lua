-- Change these:
local jid, password = "user@example.com", "secret";

-- This line squishes verse each time you run,
-- handy if you're hacking on Verse itself
--os.execute("squish --minify-level=none");

require "verse".init("client");

c = verse.new();
c:add_plugin("version");
c:add_plugin("pep");

-- Add some hooks for debugging
c:hook("opened", function () print("Stream opened!") end);
c:hook("closed", function () print("Stream closed!") end);
c:hook("stanza", function (stanza) print("Stanza:", stanza) end);

-- This one prints all received data
c:hook("incoming-raw", print, 1000);

-- Print a message after authentication
c:hook("authentication-success", function () print("Logged in!"); end);
c:hook("authentication-failure", function (err) print("Failed to log in! Error: "..tostring(err.condition)); end);

-- Print a message and exit when disconnected
c:hook("disconnected", function () print("Disconnected!"); os.exit(); end);

-- Now, actually start the connection:
c:connect_client(jid, password);

-- Catch the "ready" event to know when the stream is ready to use
c:hook("ready", function ()
	print("Stream ready!");
	c.version:set{ name = "verse example client" };
	c:hook_pep("http://jabber.org/protocol/mood", function (event)
		print(event.from.." is "..event.item.tags[1].name);
	end);
	
	c:hook_pep("http://jabber.org/protocol/tune", function (event)
		print(event.from.." is listening to "..event.item:get_child_text("title"));
	end);

	c:send(verse.presence());

	c:publish_pep(verse.stanza("tune", { xmlns = "http://jabber.org/protocol/tune" })
		:tag("title"):text("Beautiful Cedars"):up()
		:tag("artist"):text("The Spinners"):up()
		:tag("source"):text("Not Quite Folk"):up()
		:tag("track"):text("4"):up()
	);
	
end);

print("Starting loop...")
verse.loop()
