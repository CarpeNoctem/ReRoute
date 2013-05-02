use Purple;
use Data::Dumper;

%PLUGIN_INFO = (
    perl_api_version => 2,
    name => 'ReRoute',
    version => '0.3p',
    summary => 'Reroute conversations in Pidgin (or other libpurple clients).',
    description => 'Automatically takes messages sent to you and sends them to someone else on your contacts list. This is configurable, and you can set up multiple routes. In fact, you can set up routes between different accounts/protocols if you wish. However a route may only go from one contact to a single other contact, rather than multiple contacts.',
    author => 'CarpeNoctem',
    url => 'http://github.com/CarpeNoctem/ReRoute',
    load => 'plugin_load',
    unload => 'plugin_unload',
    plugin_action_sub => "plugin_actions_cb",
    prefs_info => "prefs_info_cb"
);
#TODO:
# Cleanup and review code.
# Port to C for version 0.3
# In future versions, maybe allow a route to go to multiple contacts. Will be ugly though... (2d array)

#GLOBAL VARS
$PluginName = $PLUGIN_INFO{'name'} . ' ' . $PLUGIN_INFO{'version'};
%RoutingTable = ();
$Paused = 0;
$prefs_root = "/plugins/core/ReRoute";
#END GLOBAL VARS

sub plugin_load {
    my $plugin = shift;
    Purple::Signal::connect(Purple::Conversations::get_handle(),"received-im-msg",$plugin,\&msg_received_cb,0);
    # In the future, perhaps load routing table from preferences...
    Purple::Debug::info("$PluginName", "plugin_load() - $PluginName Plugin Loaded.\n");
    
    #Add plugin preferences
    # This is necessary to create each level in the preferences tree.
    Purple::Prefs::add_none("$prefs_root");
    # Save routing tables between sessions
    Purple::Prefs::add_int("$prefs_root/save_routes",0);
    # Overwrite vs. Ignore routes with same From contact
    Purple::Prefs::add_int("$prefs_root/overwrite_routes",1);
    # [Pre|post]fix messages with "ReRouted from $user"
    Purple::Prefs::add_int("$prefs_root/notify_recipient",0);
    
    # For now, this is where saved routes will go...
    Purple::Prefs::add_string("$prefs_root/routes","");
    
    my $route_csv = Purple::Prefs::get_string("$prefs_root/routes");
    my $save_routes = Purple::Prefs::get_int("$prefs_root/save_routes");
    if ($save_routes != 0 && $route_csv ne "") {
        my @routes = split(';', $route_csv);
        Purple::Debug::info("$PluginName", "plugin_load() - Loading ".@routes." previously saved routes...\n");
        foreach my $route ( @routes ) {
            my @from_to = split(',',$route,2);
            $RoutingTable{$from_to[0]} = $from_to[1];
        }
        Purple::Debug::info("$PluginName", "plugin_load() - Current routing table:\n".Dumper(%RoutingTable));
    }
}

sub plugin_unload {
    my $plugin = shift;
    
    if (Purple::Prefs::get_int("$prefs_root/save_routes") != 0) {
        Purple::Debug::info("$PluginName", "plugin_unload() - Saving routes...\n");
        my $routes_saved = "";
        for my $from ( keys %RoutingTable ) {
            $routes_saved .= "$from,".$RoutingTable{$from}.';';
        }
        Purple::Prefs::set_string("$prefs_root/routes",$routes_saved);
        Purple::Debug::info("$PluginName", "plugin_unload() - Saved routing table:\n".Dumper(%RoutingTable));
    }
    Purple::Debug::info("$PluginName", "plugin_unload() - $PluginName Plugin Unloaded.\n");
}

sub plugin_actions_cb {
    my @actions = ('Add Route', 'Remove Route', 'Pause/Unpause ReRouting');
}

%plugin_actions = (
    'Add Route' => \&add_route_cb,
    'Remove Route' => \&remove_route_cb,
    'Pause/Unpause ReRouting' => \&pause_cb,
);

sub prefs_info_cb {
    my $frame = Purple::PluginPref::Frame->new();
    my $ppref = Purple::PluginPref->new_with_label("ReRoute Preferences");
    $frame->add($ppref);
    
    # Save routing tables between sessions
    $ppref = Purple::PluginPref->new_with_name_and_label(
        "$prefs_root/save_routes", "Save routes between sessions:");
    $ppref->set_type(1); # type: choice
    $ppref->add_choice("Yes", 1);
    $ppref->add_choice("No", 0);
    $frame->add($ppref);

    # Overwrite vs. Ignore routes with same From contact
    $ppref = Purple::PluginPref->new_with_name_and_label(
        "$prefs_root/overwrite_routes", "When adding a route with an existing \"From\" contact:");
    $ppref->set_type(1); # type: choice
    $ppref->add_choice("Overwrite previous route", 1);
    $ppref->add_choice("Don't add new route", 0);
    $frame->add($ppref);

    # Prefix messages with "ReRouted from $user:"
    $ppref = Purple::PluginPref->new_with_name_and_label(
        "$prefs_root/notify_recipient", "Notify recipients of ReRouted messages:");
    $ppref->set_type(1); # type: choice
    $ppref->add_choice("No", 0);
    $ppref->add_choice("Prepend", 1);
    $ppref->add_choice("Append", 2);
    $frame->add($ppref);
    
    return $frame;
}

sub add_route_cb {
    my $plugin = shift;
    Purple::Debug::info("$PluginName", "add_route_cb() - Adding route...\n");
    my @accts = Purple::Accounts::get_all_active();
    my %buddy_hash; #um... i guess this probably isn't really needed, by the way i ended up doing things...
    my @buddy_array;
    
    foreach my $acct ( @accts ) {
        push(@buddy_array, Purple::Find::buddies($acct, undef)); # push all buddies for this acct onto the buddy_array
        push(@{ $buddy_hash{$acct->get_username()} }, Purple::Find::buddies($acct, undef));
        my $len = $#{ $buddy_hash{$acct->get_username()}} + 1;
        Purple::Debug::info("$PluginName", "add_route_cb() - Buddies for ".$acct->get_username().": $len\n");
    }

    for my $bud ( @buddy_array ) {
        $bud = Purple::BuddyList::Buddy::get_name($bud);
    }
    @buddy_array = sort(@buddy_array);
    
    my $group = Purple::Request::Field::Group::new(2,'');
    my $spacer = '                    ';
    my $field_from = Purple::Request::Field::list_new("from_contact", "from_contact", "Choose contact from whom to route messages:");
    my $field_to = Purple::Request::Field::list_new("to_contact", "to_contact", "Choose contact to route messages to:");

    my $i = 1;
    for my $bud ( @buddy_array ) {
        Purple::Request::Field::list_add($field_from, "$bud",$i);
        Purple::Request::Field::list_add($field_to, "$bud",$i);
        $i += 1;
    }
    Purple::Request::Field::set_required($field_from, 1);
    Purple::Request::Field::set_required($field_to, 1);
    Purple::Request::Field::list_set_multi_select($field_from, 0);
    Purple::Request::Field::list_set_multi_select($field_to, 0);
    Purple::Request::Field::Group::add_field($group, $field_from);
    Purple::Request::Field::Group::add_field($group, $field_to);
    
    my $field_bidirectional = Purple::Request::Field::bool_new("bidirectional", "bidirectional", "Also add opposite of this route. (Make this bi-directional.)", 0);
    Purple::Request::Field::Group::add_field($group, $field_bidirectional);

    my $request = Purple::Request::Fields->new();
    Purple::Request::Fields::add_group($request, $group);
    
    Purple::Request::fields($plugin, $PluginName, 'Add Route', '', $request, 'OK','route_added_cb','Cancel','cancelled_cb');
}

sub route_added_cb {
    my $fields = shift;
    my $to_acct = "";
    my $to_protocol = "";
    
    my $field = Purple::Request::Fields::get_field($fields, "from_contact");
    my @vals = $field->list_get_selected();
    my $from_contact = $vals[0];

    $field = Purple::Request::Fields::get_field($fields, "to_contact");
    @vals = $field->list_get_selected();
    my $to_contact = $vals[0];
    
    my $bidirectional = Purple::Request::Fields::get_bool($fields,"bidirectional");
    
    if ( exists $RoutingTable{$from_contact} )
    {
        if (Purple::Prefs::get_int("$prefs_root/overwrite_routes") != 0) {
            Purple::Debug::info("$PluginName","route_added_cb() - $from_contact already in routing table. Overwriting...\n");
        } else {
            Purple::Debug::info("$PluginName","route_added_cb() - $from_contact already in routing table. Not adding new route.\n");
            return('');
        }
    }
    if ( $from_contact eq '' || $to_contact eq '' )
    {
        #not sure why Purple::Request::Field::set_required isn't working..
        Purple::Debug::info("$PluginName","route_added_cb() - Must select both a FROM and a TO contact.\n");
        return('');
    }
    #else...
    Purple::Debug::info("$PluginName", "route_added_cb() - Adding route from $from_contact to $to_contact\n");

    my @accts = Purple::Accounts::get_all_active();
    foreach my $acct ( @accts ) {
        my $budd = Purple::Find::buddy($acct, $to_contact);
        if ( $budd ne '' )
        {
            $to_acct = $acct->get_username();
            $to_protocol = $acct->get_protocol_id();
            last; #break
        }
    }
    
    $RoutingTable{$from_contact} = "$to_acct,$to_protocol,$to_contact";
    
    if ($bidirectional) {
        Purple::Debug::info("$PluginName", "route_added_cb() - Bi-Directional selected. Adding route from $to_contact to $from_contact\n");
        foreach my $acct ( @accts ) {
            my $budd = Purple::Find::buddy($acct, $from_contact);
            if ( $budd ne '' )
            {
                $to_acct = $acct->get_username();
                $to_protocol = $acct->get_protocol_id();
                last; #break
            }
        }
        $RoutingTable{$to_contact} = "$to_acct,$to_protocol,$from_contact";
    }
    
    Purple::Debug::info("$PluginName", "route_added_cb() - Current routing table:\n".Dumper(%RoutingTable));
    #debated whether or not to add a "route added" notification to the user here...
}

sub remove_route_cb {
    my $plugin = shift;
    Purple::Debug::info("$PluginName", "remove_route_cb() - Removing route...\n");
    
    my $group = Purple::Request::Field::Group::new(2,'');
    my $spacer = '                                                                                        ';
    my $field_route = Purple::Request::Field::list_new("route", "route", "Choose route(s) to remove:$spacer");
    
    my $i = 1;
    for my $from ( keys %RoutingTable ) {
        my @to = split(',', $RoutingTable{$from});
        $to = pop(@to);
        Purple::Request::Field::list_add($field_route, "$from -> $to",$i);
        $i += 1;
    }
    Purple::Request::Field::set_required($field_route, 1);
    Purple::Request::Field::list_set_multi_select($field_route, 1);
    Purple::Request::Field::Group::add_field($group, $field_route);

    my $request = Purple::Request::Fields->new();
    Purple::Request::Fields::add_group($request, $group);
    
    Purple::Request::fields($plugin, $PluginName, 'Remove Route', '(Multi-select allowed. Use Ctrl+A to select all.)', $request, 'OK','route_removed_cb','Cancel','cancelled_cb');
}

sub route_removed_cb {
    my $fields = shift;
    
    my $field = Purple::Request::Fields::get_field($fields, "route");
    my @vals = $field->list_get_selected();
    
    foreach my $route ( @vals )
    {
        Purple::Debug::info("$PluginName", "route_removed_cb() - Removing route, '$route'\n");
        my ($from) = split(' ',$route);
        delete $RoutingTable{$from};
    }
    Purple::Debug::info("$PluginName", "route_removed_cb() - Current routing table:\n".Dumper(%RoutingTable));
}

sub pause_cb {
    my $plugin = shift;
    #Purple icon types:
    #PURPLE_NOTIFY_MSG_ERROR = 0; PURPLE_NOTIFY_MSG_WARNING = 1; PURPLE_NOTIFY_MSG_INFO = 2; NO_ICON >= 3;
    if ($Paused) {
        $Paused = 0;
        #delete $plugin_actions{'Un-Pause ReRouting'};
        #$plugin_actions{'Pause ReRouting'} = \&pause_cb;
        # ^^^ Wanted to change the menu option, but it didn't seem to want to work...
        Purple::Debug::info("$PluginName", "pause_cb() - ReRouting Un-Paused.\n");
        #this notify box has annoyed me in the past... might remove it.
        Purple::Notify::message($plugin, 3,$PluginName, 'ReRouting Un-Paused.', '', 'cancelled_cb', undef);
    }
    else {
        $Paused = 1;
        #delete $plugin_actions{'Pause ReRouting'};
        #$plugin_actions{'Un-Pause ReRouting'} = \&pause_cb;
        # ^^^ Wanted to change the menu option, but it didn't seem to want to work...
        Purple::Debug::info("$PluginName", "pause_cb() - ReRouting Paused.\n");
        Purple::Notify::message($plugin, 3,$PluginName, 'ReRouting Paused.', '', 'cancelled_cb', undef);
    }
}

sub msg_received_cb {
    my ($account, $sender, $message, $conv, $flags, $data) = @_;
    my $slash_ind = index($sender, '/');
    if ($slash_ind > 0) {
        $sender = substr($sender, 0, $slash_ind);
    }
    if ($Paused) {
        Purple::Debug::info("$PluginName", "msg_received_cb() - ReRouting paused. Message not re-routed.\n");
    }
    else {
        if ( exists $RoutingTable{$sender} ) {
            my ($to_acct, $protocol, $route_to) = split(',', $RoutingTable{$sender});
            Purple::Debug::info("$PluginName", "msg_received_cb() - ReRouting $message from $sender to $route_to.\n");
            $to_acct = Purple::Accounts::find($to_acct,$protocol);
            my $conv1 = Purple::Conversation->new(1, $to_acct, "$route_to");
            my $im = $conv1->get_im_data();
            my $notify_recipient = Purple::Prefs::get_int("$prefs_root/notify_recipient");
            if ($notify_recipient != 0) {
                my $from = Purple::Find::buddy($account, $sender);
                $from = Purple::BuddyList::Buddy::get_local_alias($from);
                if ($notify_recipient == 1) {
                    $message = "[ReRouted from $from] " . $message;
                } else {
                    $message .= " (ReRouted from $from)";
                }
            }
            $im->send("$message");
        }
        else {
            Purple::Debug::info("$PluginName", "msg_received_cb() - Sender, $sender, not in routing table.\n");
        }
    }
}

sub cancelled_cb {
    Purple::Debug::info("$PluginName", "...Action Cancelled.\n");
}
