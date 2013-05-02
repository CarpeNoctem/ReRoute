ReRoute
=======

Version: 0.2  
Author: CarpeNoctem  
Website: http://github.com/CarpeNoctem/ReRoute  

------------
Description:
------------
ReRoute is a plugin for the Pidgin instant messaging client, or any other libpurple client, that automatically takes messages sent to you and sends them to someone else on your contacts list. This is configurable, and you can set up multiple routes. However a route may only go from one contact to a single other contact, rather than multiple contacts.

-------------------
How to use ReRoute:
-------------------
To use ReRoute, you must have perl installed on your system. If you're using Windows, this may mean you need to download and install the latest copy of ActivePerl (http://tinyurl.com/activeper1)

To install the plugin under *nix, save the reroute-0.2.pl to ~/.purple/plugins or $PREFIX/lib/purple.
For Windows, save it to %ProgramFiles%\Pidgin\plugins\

After you've copied the file, open the Plugins dialog in Pidgin. (Tools->Plugins)
If you copied it to the correct location and have perl on your system, "ReRoute" will appear in the list and you will be able to load it by clicking the checkbox next to it.

Once you've got ReRoute enabled in Pidgin, you will see a new menu under Tools, called "ReRoute".
This enables you to do 3 things: Add a route, remove routes, and pause re-routing.

#Add Route#
By clicking "Add Route", you'll be presented with two list boxes. Upon selecting a username from each box and clicking "OK", a new route will be set up, and now all messages you receive from the username you selected in the first box will get sent automatically to the username selected in the 2nd box.
Tip: When one of the boxes is selected, you can get to a username quicker than scrolling by starting to type that username.
It should be noted that in this version of ReRoute, all routes will be cleared when ReRoute is disabled or Pidgin is quit.

#Remove Route#
By clicking "Remove Route", you are given a box with your current routes. You can select any number of these. (Tip, you can even use Ctrl+A to select and remove all routes.)
Once you click "OK", the selected route(s) will be removed.


#Pause Routing#
Clicking "Pause/Unpause ReRouting" pauses or unpauses re-routing of messages. While paused, messages will no longer be sent automatically when received. Once unpaused, messages will once again be re-routed. Note that any messages received while paused do not get held, and will not be re-routed.

---------
Feedback:
---------
If you are using a libpurple chat client other than Pidgin, or an OS other than Windows, I'd love to hear from you. Even if you do not fit into this category, feel free to mention me on GitHub.

----------
Donations:
----------
This plugin is FREE! You can find it and many other project of mine (also free) at http://github.com/CarpeNoctem
