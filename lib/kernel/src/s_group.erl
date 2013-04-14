%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1998-2011. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
-module(s_group).

%% Groups nodes into s_groups with an own global name space.

-behaviour(gen_server).

%% External exports
-export([start/0, start_link/0, stop/0, init/1]).
-export([handle_call/3, handle_cast/2, handle_info/2, 
	 terminate/2, code_change/3]).

-export([register_name/3, register_name_external/3,
	 unregister_name/2, unregister_name_external/2,
	 re_register_name/3,
	 send/3, send/4,
	 whereis_name/2, whereis_name/3,
	 registered_names/1,
	 s_groups/0,
	 own_nodes/0, own_nodes/1,
	 own_s_groups/0,
	 sync/0,

	 %% Check
	 info/0,
	 monitor_nodes/1,
	 new_s_group/2, delete_s_group/1, add_nodes/2, remove_nodes/2]).

-export([publish_on_nodes/0,
	 get_own_nodes/0, get_own_nodes_with_errors/0,
         get_own_s_groups_with_nodes/0,
	 s_group_state/0,
	 ng_pairs/1,
	 new_s_group_check/3, delete_s_group_check/1, add_nodes_check/3, remove_nodes_check/2]).

%% Delete?
-export([s_groups_changed/1]).
-export([s_groups_added/1]).
-export([s_groups_removed/1]).
-export([ng_add_check/2, ng_add_check/3]).
-export([config_scan/1, config_scan/2]).
-export([registered_names_test/1]).
-export([send_test/2]).
-export([whereis_name_test/1]).

%% Internal exports
-export([sync_init/4]).


-define(cc_vsn, 2).

-define(debug(_), ok).

%%-define(debug(Term), erlang:display(Term)).

%%%====================================================================================

%-type publish_type() :: 'hidden' | 'normal'.
-type publish_type() :: 'normal'.
-type sync_state()   :: 'no_conf' | 'synced'.

-type group_name()  :: atom().
-type group_tuple() :: {GroupName :: group_name(), [node()]}
                     | {GroupName :: group_name(),
                        PublishType :: publish_type(),
                        [node()]}.

%%%====================================================================================
%%% The state of the s_group process
%%% 
%%% sync_state =  no_conf (s_groups not defined, inital state) |
%%%               synced 
%%% group_name =  Own global group name
%%% nodes =       Nodes in the own global group
%%% no_contact =  Nodes which we haven't had contact with yet
%%% sync_error =  Nodes which we haven't had contact with yet
%%% other_grps =  list of other global group names and nodes, [{otherName, [Node]}]
%%% node_name =   Own node 
%%% monitor =     List of Pids requesting nodeup/nodedown
%%%====================================================================================

-record(state, {sync_state = no_conf        :: sync_state(),
		connect_all                 :: boolean(),
		group_names = []            :: [group_name()],  %% type changed by HL;
		nodes = []                  :: [node()],
		no_contact = []             :: [node()],
		sync_error = []             :: [node()],
		other_grps = []             :: [{group_name(), [node()]}],
                own_grps =[]                :: [{group_name(), [node()]}], %% added by HL;
		node_name = node()          :: node(),
		monitor = []                :: [pid()],
		publish_type = normal       :: publish_type(),
		group_publish_type = normal :: publish_type()}).



%%%====================================================================================
%%% External exported
%%%====================================================================================

-spec s_groups() ->  {OwnGroupNames, GroupNames}  | undefined when
    OwnGroupNames :: [group_name()],
    GroupNames :: [group_name()].
s_groups() ->
    request(s_groups).

-spec monitor_nodes(Flag) -> 'ok' when
      Flag :: boolean().
monitor_nodes(Flag) -> 
    case Flag of
	true -> request({monitor_nodes, Flag});
	false -> request({monitor_nodes, Flag});
	_ -> {error, not_boolean}
    end.

-spec own_nodes() -> Nodes when
      Nodes :: [Node :: node()].
own_nodes() ->
    request({own_nodes}).

-spec own_nodes(SGroupName) -> Nodes when
      SGroupName :: group_name(),
      Nodes :: [Node :: node()].
own_nodes(SGroupName) ->
    request({own_nodes, SGroupName}).

-spec own_s_groups() -> GroupTuples when
      GroupTuples :: [GroupTuple :: group_tuple()].
own_s_groups() ->
    request(own_s_groups).

-type name()  :: atom().
-type where() :: {'node', node()} | {'group', group_name()}.

-spec registered_names(Where) -> Names when
      Where :: where(),
      Names :: [Name :: name()].
registered_names(Arg) ->
    request({registered_names, Arg}).

-spec send(Name, SGroupName, Msg) -> Pid | {badarg, {Name, SGroupName, Msg}} when
      Name :: name(),
      SGroupName :: group_name(),
      Msg :: term(),
      Pid :: pid().
send(Name, SGroupName, Msg) ->
    request({send, Name, SGroupName, Msg}).

-spec send(Node, Name, SGroupName, Msg) -> Pid | {badarg, {Name, SGroupName, Msg}} when
      Node :: node(),
      Name :: name(),
      SGroupName :: group_name(),
      Msg :: term(),
      Pid :: pid().
send(Node, Name, SGroupName, Msg) ->
    request({send, Node, Name, SGroupName, Msg}).




-spec register_name(Name, SGroupName, Pid) -> 'yes' | 'no' when	%NC
      Name :: term(),
      SGroupName :: group_name(),
      Pid :: pid().
register_name(Name, SGroupName, Pid) when is_pid(Pid) ->
    request({register_name, Name, SGroupName, Pid}).

-spec register_name_external(Name, SGroupName, Pid) -> 'yes' | 'no' when	%NC
      Name :: term(),
      SGroupName :: group_name(),
      Pid :: pid().
register_name_external(Name, SGroupName, Pid) when is_pid(Pid) ->
    request({register_name_external, Name, SGroupName, Pid}).

-spec unregister_name(Name, SGroupName) -> _ when
      Name :: term(),
      SGroupName :: group_name().
unregister_name(Name, SGroupName) ->
      request({unregister_name, Name, SGroupName}).

unregister_name_external(Name, SGroupName) ->
      request({unregister_name, Name, SGroupName}).

-spec re_register_name(Name, SGroupName, Pid) -> 'yes' | 'no' when
      Name :: term(),
      SGroupName :: group_name(),
      Pid :: pid().
re_register_name(Name, SGroupName, Pid) when is_pid(Pid) ->
      request({re_register_name, Name, SGroupName, Pid}).

-spec whereis_name(Name, SGroupName) -> pid() | 'undefined' when
      Name :: name(),
      SGroupName :: group_name().
whereis_name(Name, SGroupName) ->
    request({whereis_name, Name, SGroupName}).

-spec whereis_name(Node, Name, SGroupName) -> pid() | 'undefined' when
      Node :: node(),
      Name :: name(),
      SGroupName :: group_name().
whereis_name(Node, Name, SGroupName) ->
    request({whereis_name, Node, Name, SGroupName}).

-spec new_s_group(SGroupName, Nodes) -> {ok, SGroupName, Nodes} |
      			                {error, Reason} when
      SGroupName :: group_name(),
      Nodes :: [Node :: node()],
      Reason :: term().

new_s_group(SGroupName, Nodes) ->
    case new_s_group1(SGroupName, Nodes) of
        ok ->
	   case add_nodes(SGroupName, Nodes--[node()]) of
	       {ok, NewNodes} -> {ok, SGroupName, NewNodes++[node()]};
	       {error, Reason} -> {error, Reason}
	   end;
	{error, Reason} -> {error, Reason}
    end.

new_s_group1(SGroupName, Nodes) ->
    request({new_s_group1, SGroupName, Nodes}).

new_s_group_check(Node, PubType, {SGroupName, Nodes}) ->
    request({new_s_group_check, Node, PubType, {SGroupName, Nodes}}).

-spec delete_s_group(SGroupName) -> 'ok' | {error, Reason} when
      SGroupName :: group_name(),
      Reason :: term().


delete_s_group(SGroupName) ->
    request({delete_s_group, SGroupName}).

delete_s_group_check(SGroupName) ->
    request({delete_s_group_check, SGroupName}).


-spec add_nodes(SGroupName, Nodes) -> {ok, Nodes} | {error, Reason} when
      SGroupName :: group_name(),
      Nodes :: [Node :: node()],
      Reason :: term().

add_nodes(SGroupName, Nodes) ->
    Result = add_nodes_conf(SGroupName, Nodes),
    ?debug({"add_nodes_Result", Result}),
    case Result of
        {ok, NewNodes} ->
	     {ok, NewNodes--(NewNodes--Nodes)};
        _ -> Result
    end.

add_nodes_conf(SGroupName, Nodes) -> 
    request({add_nodes, SGroupName, Nodes}).

add_nodes_check(Node, PubType, {SGroupName, Nodes}) ->
    request({add_nodes_check, Node, PubType, {SGroupName, Nodes}}).

s_group_state() ->
    request({s_group_state}).

-spec remove_nodes(SGroupName, Nodes) -> 'ok' | {error, Reason} when
      SGroupName :: group_name(),
      Nodes :: [Node :: node()],
      Reason :: term().

remove_nodes(SGroupName, Nodes) ->
    request({remove_nodes, SGroupName, Nodes}).

remove_nodes_check(SGroupName, Nodes) ->
    request({remove_nodes_check, SGroupName, Nodes}).



s_groups_changed(NewPara) ->
    request({s_groups_changed, NewPara}).

s_groups_added(NewPara) ->
    request({s_groups_added, NewPara}).

s_groups_removed(NewPara) ->
    request({s_groups_removed, NewPara}).

-spec sync() -> 'ok'.
sync() ->
    request(sync).

ng_add_check(Node, OthersNG) ->
    ng_add_check(Node, normal, OthersNG).

ng_add_check(Node, PubType, OthersNG) ->
    request({ng_add_check, Node, PubType, OthersNG}).

-type info_item() :: {'state', 	 	  State :: sync_state()}
                   | {'own_group_names',  GroupName :: [group_name()]}
                   | {'own_group_nodes',  Nodes :: [node()]}
                   | {'synched_nodes', 	  Nodes :: [node()]}
                   | {'sync_error', 	  Nodes :: [node()]}
                   | {'no_contact', 	  Nodes :: [node()]}
                   | {'own_s_groups', 	  OwnGroups::[group_tuple()]}
                   | {'other_groups', 	  Groups :: [group_tuple()]}
                   | {'monitoring', 	  Pids :: [pid()]}.

-spec info() -> [info_item()].
info() ->
    request(info, 3000).

%% ==== ONLY for test suites ====
registered_names_test(Arg) ->
    request({registered_names_test, Arg}).
send_test(Name, Msg) ->
    request({send_test, Name, Msg}).
whereis_name_test(Name) ->
    request({whereis_name_test, Name}).
%% ==== ONLY for test suites ====


request(Req) ->
    request(Req, infinity).

request(Req, Time) ->
    case whereis(s_group) of
	P when is_pid(P) ->
	    gen_server:call(s_group, Req, Time);
	_Other -> 
	    {error, s_group_not_runnig}
    end.

%%%====================================================================================
%%% gen_server start
%%%
%%% The first thing to happen is to read if the s_groups key is defined in the
%%% .config file. If not defined, the whole system is started as one s_group, 
%%% and the services of s_group are superfluous.
%%% Otherwise a sync process is started to check that all nodes in the own global
%%% group have the same configuration. This is done by sending 'conf_check' to all
%%% other nodes and requiring 'conf_check_result' back.
%%% If the nodes are not in agreement of the configuration the s_group process 
%%% will remove these nodes from the #state.nodes list. This can be a normal case
%%% at release upgrade when all nodes are not yet upgraded.
%%%
%%% It is possible to manually force a sync of the s_group. This is done for 
%%% instance after a release upgrade, after all nodes in the group beeing upgraded.
%%% The nodes are not synced automatically because it would cause the node to be
%%% disconnected from those not yet beeing upgraded.
%%%
%%% The three process dictionary variables (registered_names, send, and whereis_name) 
%%% are used to store information needed if the search process crashes. 
%%% The search process is a help process to find registered names in the system.
%%%====================================================================================
start() -> gen_server:start({local, s_group}, s_group, [], []).
start_link() -> gen_server:start_link({local, s_group},s_group,[],[]).
stop() -> gen_server:call(s_group, stop, infinity).

init([]) ->
    process_flag(priority, max),
    ok = net_kernel:monitor_nodes(true),
    put(registered_names, [undefined]),
    put(send, [undefined]),
    put(whereis_name, [undefined]),
    process_flag(trap_exit, true),
    Ca = case init:get_argument(connect_all) of
	     {ok, [["false"]]} ->
		 false;
	     _ ->
		 true
	 end,
    PT = publish_arg(),
    case application:get_env(kernel, s_groups) of
	undefined ->
	    update_publish_nodes(PT),
	    {ok, #state{publish_type = PT,
			connect_all = Ca}};
	{ok, []} ->
	    update_publish_nodes(PT),
	    {ok, #state{publish_type = PT,
			connect_all = Ca}};
	{ok, NodeGrps} ->
            case catch config_scan(NodeGrps, publish_type) of
                {error, _Error2} ->
                    update_publish_nodes(PT),
                    exit({error, {'invalid g_groups definition', NodeGrps}});
                {ok, DefOwnSGroupsT, DefOtherSGroupsT} ->
                    %%?debug({".config file scan result:",  {ok, DefOwnSGroupsT, DefOtherSGroupsT}}),
                    DefOwnSGroupsT1 = [{GroupName,GroupNodes}||
                                          {GroupName, _PubType, GroupNodes}
                                              <- DefOwnSGroupsT],
                    {DefSGroupNamesT1, DefSGroupNodesT1}=lists:unzip(DefOwnSGroupsT1),
                    DefSGroupNamesT = lists:usort(DefSGroupNamesT1),
                    DefSGroupNodesT = lists:usort(lists:append(DefSGroupNodesT1)),
                    update_publish_nodes(PT, {normal, DefSGroupNodesT}),
                    %% First disconnect any nodes not belonging to our own group
                    disconnect_nodes(nodes(connected) -- DefSGroupNodesT),
                    lists:foreach(fun(Node) ->
                                          erlang:monitor_node(Node, true)
                                  end,
                                  DefSGroupNodesT),
                    NewState = #state{sync_state = synced,
				      group_names = DefSGroupNamesT,
                                      own_grps = DefOwnSGroupsT1,
                                      other_grps = DefOtherSGroupsT,
                                      no_contact = lists:delete(node(), DefSGroupNodesT),
				      publish_type = PT,
		    	              group_publish_type = normal
				      },
                    %%?debug({"NewState", NewState}),
                    {ok, NewState}
            end
    end.
                        


%%%====================================================================================
%%% sync() -> ok 
%%%
%%% An operator ordered sync of the own s_group. This must be done after
%%% a release upgrade. It can also be ordered if something has made the nodes
%%% to disagree of the s_groups definition.
%%%====================================================================================
handle_call(sync, _From, S) ->
    %%?debug({"sync:",[node(), application:get_env(kernel, s_groups)]}),
    case application:get_env(kernel, s_groups) of
	undefined ->
	    update_publish_nodes(S#state.publish_type),
	    {reply, ok, S};
	{ok, []} ->
	    update_publish_nodes(S#state.publish_type),
	    {reply, ok, S};
	{ok, NodeGrps} ->
	    {DefGroupNames, PubTpGrp, DefNodes, DefOwn, DefOther} = 
		case catch config_scan(NodeGrps, publish_type) of
		    {error, _Error2} ->
			exit({error, {'invalid s_groups definition', NodeGrps}});
                    {ok, DefOwnSGroupsT, DefOtherSGroupsT} ->
                        DefOwnSGroupsT1 = [{GroupName,GroupNodes}||
                                              {GroupName, _PubType, GroupNodes}
                                                  <- DefOwnSGroupsT],
                        {DefSGroupNamesT1, DefSGroupNodesT1}=lists:unzip(DefOwnSGroupsT1),
                        DefSGroupNamesT = lists:usort(DefSGroupNamesT1),
                        DefSGroupNodesT = lists:usort(lists:append(DefSGroupNodesT1)),
                        PubType = normal,
                        update_publish_nodes(S#state.publish_type, {PubType, DefSGroupNodesT}),
			?debug({"sync_nodes_connected_DefSGroupNodesT",
			              nodes(connected), DefSGroupNodesT}),
                        %% First inform global on all nodes not belonging to our own group
			disconnect_nodes(nodes(connected) -- DefSGroupNodesT),
			%% Sync with the nodes in the own group
                        kill_s_group_check(),
                        Pid = spawn_link(?MODULE, sync_init, 
					 [sync, DefSGroupNamesT, PubType, DefOwnSGroupsT1]),
			?debug({"sync_DefSGroupNamesT_PubType_DefOwnSGroupsT1",
			              DefSGroupNamesT, PubType, DefOwnSGroupsT1}),
			register(s_group_check, Pid),
                        {DefSGroupNamesT, PubType, 
                         lists:delete(node(), DefSGroupNodesT),
                         DefOwnSGroupsT1, DefOtherSGroupsT}
                end,
            {reply, ok, S#state{sync_state = synced,
	    	    		group_names = DefGroupNames, 
				no_contact = lists:sort(DefNodes), 
                                own_grps = DefOwn,
				other_grps = DefOther,
				group_publish_type = PubTpGrp}}
    end;



%%%====================================================================================
%%% Get the names of the s_groups
%%%====================================================================================
handle_call(s_groups, _From, S) ->
    Result = case S#state.sync_state of
		 no_conf ->
		     undefined;
		 synced ->
		     Other = lists:foldl(fun({N,_L}, Acc) -> Acc ++ [N]
					 end,
					 [], S#state.other_grps),
		     {S#state.group_names, Other}
	     end,
    {reply, Result, S};


%%%====================================================================================
%%% monitor_nodes(bool()) -> ok 
%%%
%%% Monitor nodes in the own global group. 
%%%   True => send nodeup/nodedown to the requesting Pid
%%%   False => stop sending nodeup/nodedown to the requesting Pid
%%%====================================================================================
handle_call({monitor_nodes, Flag}, {Pid, _}, StateIn) ->
    %%io:format("***** handle_call ~p~n",[monitor_nodes]),
    {Res, State} = monitor_nodes(Flag, Pid, StateIn),
    {reply, Res, State};


%%%====================================================================================
%%% own_nodes() -> [Node]
%%% own_nodes(SGroupName) -> [Node] 
%%%
%%% Get a list of nodes in the own s_groups
%%%====================================================================================
handle_call({own_nodes}, _From, S) ->
    Nodes = case S#state.sync_state of
		no_conf ->
		    [node() | nodes(connected)];
		synced ->
		    get_own_nodes()
	    end,
    {reply, Nodes, S};

handle_call({own_nodes, SGroupName}, _From, S) ->
    Nodes = case S#state.sync_state of
		no_conf ->
		    [];
		synced ->
		       case lists:member(SGroupName, S#state.group_names) of
		       	    true ->
			    	{SGroupName, Nodes1} = lists:keyfind(SGroupName, 1, S#state.own_grps),
				Nodes1;
			    _ ->
				[]
		       end
	    end,
    {reply, Nodes, S};


%%%====================================================================================
%%% own_s_groups() -> [GroupTuples] 
%%%
%%% Get a list of own group_tuples
%%%====================================================================================
handle_call(own_s_groups, _From, S) ->
    GroupTuples = case S#state.sync_state of
		no_conf ->
		    [];
		synced ->
		    S#state.own_grps
	    end,
    {reply, GroupTuples, S};

%%%====================================================================================
%%% registered_names({node, Node}) -> [Name] | {error, ErrorMessage}
%%% registered_names({s_group, SGroupName}) -> [Name] | {error, ErrorMessage}
%%%
%%% Get the registered names from a specified Node or SGroupName.
%%%====================================================================================
handle_call({registered_names, {s_group, SGroupName}}, From, S) ->
    case lists:member(SGroupName, S#state.group_names) of 
        true ->
	    Res = s_group_names(global:registered_names(all_names), [], SGroupName),
            {reply, Res, S};
        false ->		 
            case lists:keysearch(SGroupName, 1, S#state.other_grps) of
                false ->
                    {reply, [], S};
                {value, {SGroupName, []}} ->
                    {reply, [], S};
                {value, {SGroupName, Nodes}} ->
                    Pid = global_search:start(names, {s_group, SGroupName, Nodes, From}),
                    Wait = get(registered_names),
                    put(registered_names, [{Pid, From} | Wait]),
                    {noreply, S}
            end
    end;
handle_call({registered_names, {node, Node}}, _From, S) when Node =:= node() ->
    Res = global:registered_names(all_names),
    {reply, Res, S};
handle_call({registered_names, {node, Node}}, From, S) ->
    Pid = global_search:start(names, {node, Node, From}),
    Wait = get(registered_names),
    put(registered_names, [{Pid, From} | Wait]),
    {noreply, S};



%%%====================================================================================
%%% send(Name, SGroupName, Msg) -> Pid | {badarg, {Name, SGroupName, Msg}}
%%% send(Node, Name, SGroupName, Msg) -> Pid | {badarg, {Name, SGroupName, Msg}}
%%%
%%% Send the Msg to the specified globally registered Name in own s_group,
%%% in specified Node, or SGroupName.
%%% But first the receiver is to be found, the thread is continued at
%%% handle_cast(send_res)
%%%====================================================================================
%% Search in the whole known world, but check own node first.
handle_call({send, Name, SGroupName, Msg}, From, S) -> %NC?
    case global:whereis_name(Name, SGroupName) of
	undefined ->
	    Pid = global_search:start(send, {any, S#state.other_grps, Name, SGroupName, Msg, From}),
	    Wait = get(send),
	    put(send, [{Pid, From, Name, SGroupName, Msg} | Wait]),
	    {noreply, S};
	Found ->
	    Found ! Msg,
	    {reply, Found, S}
    end;

%% Search on the specified node.
handle_call({send, Node, Name, SGroupName, Msg}, From, S) ->
    Pid = global_search:start(send, {node, Node, Name, SGroupName, Msg, From}),
    Wait = get(send),
    put(send, [{Pid, From, Name, SGroupName, Msg} | Wait]),
    {noreply, S};


%%%====================================================================================
%%% register_name(Name, SGroupName, Pid) -> 'yes' | 'no'
%%% register_name_external(Name, SGroupName, Pid) -> 'yes' | 'no'
%%% unregister_name(Name, SGroupName) -> _
%%% re_register_name(Name, SGroupName, Pid) -> 'yes' | 'no'
%%%
handle_call({register_name, Name, SGroupName, Pid}, _From, S) ->
    case lists:member(SGroupName, S#state.group_names) of
        true ->
            Res = global:register_name(Name, SGroupName, Pid, fun global:random_exit_name/3),
            {reply, Res, S};
        _ ->
            {reply, no, S}
    end;

handle_call({register_name_external, Name, SGroupName, Pid}, _From, S) ->
    case lists:member(SGroupName, S#state.group_names) of
        true ->
            Res = global:register_name_external(Name, SGroupName, Pid, fun global:random_exit_name/3),
            {reply, Res, S};
        _ ->
            {reply, no, S}
    end;

handle_call({unregister_name, Name, SGroupName}, _From, S) ->
    case lists:member(SGroupName, S#state.group_names) of
        true ->
            Res = global:unregister_name(Name, SGroupName),
            {reply, Res, S};
        _ ->
            {reply, no, S}
    end;

handle_call({re_register_name, Name, SGroupName, Pid}, _From, S) ->
    case lists:member(SGroupName, S#state.group_names) of
        true ->
            Res = global:re_register_name(Name, SGroupName, Pid, fun global:random_exit_name/3),
            {reply, Res, S};
        _ ->
            {reply, no, S}
    end;
%%%====================================================================================
%%% whereis_name(Name, SGroupName) -> Pid | undefined
%%% whereis_name(Node, Name, SGroupName) -> Pid | undefined
%%%
%%% Get the Pid of a globally registered Name in own s_group,
%%% in specified Node, or SGroupName.
%%% But first the process is to be found, 
%%% the thread is continued at handle_cast(find_name_res)
%%%====================================================================================
%% Search on the specified node.
handle_call({whereis_name, Node, Name, SGroupName}, From, S) ->
    Pid = global_search:start(whereis, {node, Node, Name, SGroupName, From}),
    Wait = get(whereis_name),
    put(whereis_name, [{Pid, From} | Wait]),
    {noreply, S};

%% Search in the whole known world, but check own node first.
handle_call({whereis_name, Name, SGroupName}, From, S) ->
    case global:whereis_name(Name, SGroupName) of
	undefined ->
	    Pid = global_search:start(whereis, {any, S#state.other_grps, Name, SGroupName, From}),
	    Wait = get(whereis_name),
	    put(whereis_name, [{Pid, From} | Wait]),
	    {noreply, S};
	Found ->
	    {reply, Found, S}
    end;


%%%====================================================================================
%%% Create a new s_group.
%%% -spec new_s_group(SGroupName, Nodes) -> 'ok' | {error, Reason}.
%%%====================================================================================
handle_call({new_s_group1, SGroupName, Nodes}, _From, S) ->
    ?debug({new_s_group1, SGroupName, Nodes}),
    case lists:member(node(), Nodes) of
        false ->
           {reply, {error, remote_s_group}, S};
        true ->
           case lists:member(SGroupName, S#state.group_names) of
	       true ->
                  {reply, {error, s_group_name_is_in_use}, S};
               false ->
                  ok = global:set_s_group_name(SGroupName),
		  %Nodes1 = Nodes -- [node()],
		  %	 ?debug({"new_s_group1_Nodes", Nodes}),
		  %	 ?debug({"new_s_group1_S#state.nodes", S#state.nodes}),
		  %	 %%?debug({"new_s_group1_", }),
		  %NewNodes = Nodes1 -- S#state.nodes,
		  %	   ?debug({"new_s_group1_nodes_connected", nodes(connected)}),
		  %	   ?debug({"new_s_group1_NewNodes", NewNodes}),
		  %	   %%NodesToDisConnect = nodes(connected) -- (Nodes ++ S#state.nodes),
		  %NodesToDisConnect = nodes(connected) -- NewNodes,
                  %force_nodedown(NodesToDisConnect),
		  %disconnect_nodes(NodesToDisConnect),
                  NewConf = mk_new_s_group_conf(SGroupName, [node()]),
                  application:set_env(kernel, s_groups, NewConf),
                  ok = global:reset_s_group_name(),
 		  NewOtherSGroups =
		      case lists:keyfind(SGroupName, 1, S#state.other_grps) of
    		          false -> S#state.other_grps;
			  _ -> lists:keydelete(SGroupName, 1, S#state.other_grps)
		      end,
    		  NoGroupNodes = global:get_known_s_group('no_group'),
    		  disconnect_nodes(NoGroupNodes),
		  %% Because of some reason the Name is unregistered
		  %% Add new SGroupTuple to global state
		  ok = global:add_s_group(SGroupName),
                  NewS = S#state{sync_state = synced,
                                 group_names = [SGroupName | S#state.group_names],
                                 own_grps = [{SGroupName, [node()]} | S#state.own_grps],
				 other_grps = NewOtherSGroups
                                 },
                  {reply, ok, NewS}
           end
    end;



handle_call({new_s_group, SGroupName, Nodes}, _From, S) ->
    ?debug({new_s_group, SGroupName, Nodes}),
    case lists:member(node(), Nodes) of
        false ->
           {reply, {error, remote_s_group}, S};
        true ->
           case lists:member(SGroupName, S#state.group_names) of
	       true ->
                  {reply, {error, s_group_name_is_in_use}, S};
               false ->
                  ok = global:set_s_group_name(SGroupName),
                  NewNodes = Nodes -- S#state.nodes,
                  force_nodedown(nodes(connected) -- NewNodes),	%% NC?
                  NewConf = mk_new_s_group_conf(SGroupName, Nodes),
                  application:set_env(kernel, s_groups, NewConf),
                  NGACArgs = [node(), normal, {SGroupName, Nodes}],
                  OtherNodes = lists:delete(node(), Nodes),
                  {NS, NNC, NSE} =
                      lists:foldl(fun(Node, {NN_acc, NNC_acc, NSE_acc}) -> 
                                     case rpc:call(Node, s_group, new_s_group_check, NGACArgs) of
                                        {badrpc, _} ->
                                            {NN_acc, [Node | NNC_acc], NSE_acc};
                                        agreed ->
                                            {[Node | NN_acc], NNC_acc, NSE_acc};
                                        not_agreed ->
                                            {NN_acc, NNC_acc, [Node | NSE_acc]}
                                     end
                            end,
                            {[], [], []}, OtherNodes),
                  ?debug({"NS_NNC_NSE1:",  {NS, NNC, NSE}}),
                  ok = global:reset_s_group_name(),
                  NewS = S#state{sync_state = synced,
                                 group_names = [SGroupName | S#state.group_names],
                                 own_grps = [{SGroupName, Nodes} | S#state.own_grps],
                                 %%nodes = lists:usort(Nodes ++ S#state.nodes),
                                 no_contact = lists:usort(NNC ++ S#state.no_contact -- NS),
                                 sync_error = lists:usort(NSE ++ S#state.sync_error -- NS)
                                 },
                  {reply, ok, NewS}
           end
    end;
 
handle_call({new_s_group_check, Node, _PubType, {SGroupName, Nodes}}, _From, S) ->
    ?debug({{new_s_group_check, Node, _PubType, {SGroupName, Nodes}}, _From, S}),
    OwnGroups = S#state.own_grps,
    %% Check OtherKnownSGroups
    case lists:member(SGroupName, OwnGroups) of 
        true ->
            {reply, {error, not_agreed}, S};
        false ->
            NewConf = mk_new_s_group_conf(SGroupName, Nodes),
            application:set_env(kernel, s_groups, NewConf),
            NewS = S#state{sync_state = synced, 
                           group_names = [SGroupName | S#state.group_names],
                           own_grps = [{SGroupName, Nodes} | OwnGroups],
			   %%other_grps = NewOtherSGroups,
                           %%nodes = lists:usort(S#state.nodes ++ Nodes),
                           no_contact = lists:delete(Node, S#state.no_contact),
                           sync_error = lists:delete(Node, S#state.sync_error) 
			   },
            ?debug({"new_s_group_check_NewS", NewS}),
            {reply, agreed, NewS}
    end; 

%%%====================================================================================
%%% Delete an s_group
%%% -spec delete_s_group(SGroupName) -> 'ok' | {error, Reason}.
%%%====================================================================================
handle_call({delete_s_group, SGroupName}, _From, S) ->
    %%?debug({delete_s_group, SGroupName}),
    case lists:member(SGroupName, S#state.group_names) of 
        false ->
            {reply, ok, S};
        true ->
            global:delete_s_group(SGroupName),
            NewConf = rm_s_group_from_conf(SGroupName),
            application:set_env(kernel, s_groups, NewConf),
            SGroupNodes = case lists:keyfind(SGroupName, 1, S#state.own_grps) of 
                             {_, Ns} -> Ns;
                             false -> []  %% this should not happen.
                         end,
            OtherSGroupNodes = lists:usort(lists:append(
			       [Ns || {G, Ns} <- S#state.own_grps, G /= SGroupName])),
            OtherNodes = lists:delete(node(), SGroupNodes),
            [rpc:call(Node, s_group, delete_s_group_check, [SGroupName]) ||
                	    	     			   	Node <- OtherNodes],
            NewS = S#state{sync_state = if length(S#state.group_names)==1 -> no_conf;
                                           true -> synced
                                        end,
                           group_names = S#state.group_names -- [SGroupName],
                           nodes = S#state.nodes -- (SGroupNodes -- OtherSGroupNodes),
                           sync_error = S#state.sync_error -- SGroupNodes, 
                           no_contact = S#state.no_contact -- SGroupNodes,
                           own_grps = S#state.own_grps -- [{SGroupName, SGroupNodes}] 
                          },
            {reply, ok, NewS}
    end;

handle_call({delete_s_group_check, SGroupName}, _From, S) ->
    %%?debug({delete_s_group_check, SGroupName}),
    global:delete_s_group(SGroupName),
    NewConf = rm_s_group_from_conf(SGroupName),
    application:set_env(kernel, s_groups, NewConf),
    SGroupNodes = case lists:keyfind(SGroupName, 1, S#state.own_grps) of 
                     {_, Ns}-> Ns;
                     false -> []  %% this should not happen.
                 end,
    OtherSGroupNodes = lists:usort(lists:append(
                           [Ns || {G, Ns} <- S#state.own_grps, G /= SGroupName])),
    NewS = S#state{sync_state = if length(S#state.group_names) == 1 -> no_conf;
                                   true -> synced
                                end, 
                   group_names = S#state.group_names -- [SGroupName],
                   nodes = S#state.nodes -- (SGroupNodes -- OtherSGroupNodes),
                   sync_error = S#state.sync_error -- SGroupNodes, 
                   no_contact = S#state.no_contact -- SGroupNodes,
                   own_grps = S#state.own_grps -- [{SGroupName, SGroupNodes}] 
                  },
    {reply, ok, NewS};

%%%====================================================================================
%%% Remove nodes from an s_group
%%% -spec remove_nodes(SGroupName, Nodes) -> 'ok' | {error, Reason}.
%%%====================================================================================
handle_call({remove_nodes, SGroupName, Nodes}, _From, S) ->
    %%?debug({remove_nodes, SGroupName, Nodes}),
    case lists:member(SGroupName, S#state.group_names) of 
        false ->
            {reply, {error, s_group_name_is_not_known}, S};
        true ->
            SGroupNodes = case lists:keyfind(SGroupName, 1, S#state.own_grps) of 
                             {_, Ns}-> Ns;
                             false -> []  %% this should not happen.
                         end, 
            OtherNodes = SGroupNodes -- [node()],
            NodesToRm = intersection(Nodes, SGroupNodes),
            NewConf = rm_s_group_nodes_from_conf(SGroupName,NodesToRm),
            application:set_env(kernel, s_groups, NewConf),
            global:remove_s_group_nodes(SGroupName, NodesToRm),
            [rpc:call(Node, s_group, remove_nodes_check, [SGroupName, NodesToRm]) ||
                Node <- OtherNodes],
            NewS = case lists:member(node(), NodesToRm) orelse NodesToRm == SGroupNodes of 
                     true ->
                         NewOwnGrps = [Ns || {G, Ns} <- S#state.own_grps, G /= SGroupName],
                         NewNodes = lists:append(element(2, lists:unzip(NewOwnGrps))),
                         S#state{sync_state = if length(S#state.group_names) == 1 -> no_conf;
                                                 true -> synced
                                              end, 
                                 group_names = S#state.group_names -- [SGroupName],
                                 nodes = NewNodes,
                                 sync_error = S#state.sync_error -- SGroupNodes, 
                                 no_contact = S#state.no_contact -- SGroupNodes,
                                 own_grps = NewOwnGrps 
                                };
                     false-> 
                         NewSGroupNodes = SGroupNodes -- NodesToRm,
                         NewOwnGrps = lists:keyreplace(SGroupName, 1, S#state.own_grps,
                                                       {SGroupName, NewSGroupNodes}),
                         NewNodes = lists:append(element(2, lists:unzip(NewOwnGrps))),
                         S#state{nodes = NewNodes,
                                 sync_error = S#state.sync_error -- NodesToRm, 
                                 no_contact = S#state.no_contact -- NodesToRm,
                                 own_grps = NewOwnGrps}
                 end,
            {reply, ok, NewS}
    end;
     
handle_call({remove_nodes_check, SGroupName, NodesToRm}, _From, S) ->
    %%?debug({{remove_nodes_check, SGroupName, NodesToRm}, _From, S}),
    NewConf = rm_s_group_nodes_from_conf(SGroupName, NodesToRm),
    application:set_env(kernel, s_groups, NewConf),
    global:remove_s_group_nodes(SGroupName, NodesToRm),
    SGroupNodes = case lists:keyfind(SGroupName, 1, S#state.own_grps) of 
                             {_, Ns}-> Ns;
                             false -> []  %% this should not happen.
                         end,
    NewS = case lists:member(node(), NodesToRm) orelse NodesToRm == SGroupNodes of 
                     true ->
                         NewOwnGrps = [Ns || {G, Ns} <- S#state.own_grps, G /= SGroupName],
                         NewNodes = lists:append(element(2, lists:unzip(NewOwnGrps))),
                         S#state{sync_state = if length(S#state.group_names) == 1 -> no_conf;
                                                 true -> synced
                                              end, 
                                 group_names = S#state.group_names -- [SGroupName],
                                 nodes = NewNodes,
                                 sync_error = S#state.sync_error -- SGroupNodes, 
                                 no_contact = S#state.no_contact -- SGroupNodes,
                                 own_grps = NewOwnGrps
                                };
                     false-> 
                         NewSGroupNodes = SGroupNodes -- NodesToRm,
                         NewOwnGrps = lists:keyreplace(SGroupName, 1, S#state.own_grps,
                                                       {SGroupName, NewSGroupNodes}),
                         NewNodes = lists:append(element(2, lists:unzip(NewOwnGrps))),
                         S#state{nodes = NewNodes,
                                 sync_error = S#state.sync_error -- NodesToRm, 
                                 no_contact = S#state.no_contact -- NodesToRm,
                                 own_grps = NewOwnGrps}
                 end,
    {reply, ok, NewS};


%%%====================================================================================
%%% Add nodes to an existing s_group.
%%% -spec add_nodes(SGroupName, Nodes) -> 'ok' | {error, Reason}.
%%%====================================================================================
handle_call({add_nodes, SGroupName, Nodes}, _From, S) ->
    %%?debug({add_nodes, SGroupName, Nodes}),
    case lists:member(SGroupName, S#state.group_names) of 
        false ->
            {reply, {error, s_group_name_does_not_exist}, S};
        true ->
            SGroupNodes = case lists:keyfind(SGroupName, 1, S#state.own_grps) of 
                             {_, Ns} -> Ns;
                             false -> []  %% this should not happen.
                          end,
            case Nodes -- SGroupNodes of 
                [] -> {reply, {ok, Nodes}, S};
                NewNodes ->
                    ok = global:set_s_group_name(SGroupName),

		    ?debug({"add_nodes_Nodes", Nodes}),
		    ?debug({"add_nodes_NewNodes", NewNodes}),
		    NodesToDisConnect = Nodes -- (Nodes -- nodes(connected)),
                    %%NodesToDisConnect = nodes(connected) -- (Nodes ++ S#state.nodes),
		    ?debug({"add_nodes_NodesToDisConnect", NodesToDisConnect}),
                    %%force_nodedown(NodesToDisConnect),
		    disconnect_nodes(NodesToDisConnect),

                    NewSGroupNodes = lists:sort(NewNodes ++ SGroupNodes),
                    NewConf = mk_new_s_group_conf(SGroupName, NewSGroupNodes),
                    ?debug({"Newconf:", NewConf}),
                    application:set_env(kernel, s_groups, NewConf),
                    NewSGroupNodes = lists:sort(NewNodes ++ SGroupNodes),
                    NGACArgs = [node(), normal, {SGroupName, NewSGroupNodes}],
                    ?debug({"NGACArgs:",NGACArgs}),
		    %% NS: agreed nodes; NNC: badrpc nodes; NSE: not_agreed nodes
                    {NS, NNC, NSE} =
                        lists:foldl(fun(Node, {NN_acc, NNC_acc, NSE_acc}) -> 
                                            case rpc:call(Node, s_group, add_nodes_check, NGACArgs) of
                                                {badrpc, _} ->
                                                    {NN_acc, [Node | NNC_acc], NSE_acc};
                                                agreed ->
                                                    {[Node | NN_acc], NNC_acc, NSE_acc};
                                                not_agreed ->
                                                    {NN_acc, NNC_acc, [Node | NSE_acc]}
                                            end
                                    end,
                                    {[], [], []}, lists:delete(node(), NewSGroupNodes)),
                    ?debug({"NS_NNC_NSE1:",  {NS, NNC, NSE}}),
		    ?debug({"add_nodes_S#state.nodes_NodesToDisConnect",
			               S#state.nodes, NodesToDisConnect}),
                    ok = global:reset_s_group_name(),
                    NewS = S#state{sync_state = synced, 
		                   %%group_names = S#state.group_names,
                                   own_grps = lists:keyreplace(SGroupName, 1,
			   	              S#state.own_grps, {SGroupName, NewSGroupNodes}),
				   %%other_grps = S#state.other_grps,
				   %% Remove newly added nodes from sync
                                   nodes = S#state.nodes--NodesToDisConnect,
                                   no_contact = lists:usort(NNC ++ S#state.no_contact -- NS),
                                   sync_error = lists:usort(NSE ++ S#state.sync_error -- NS)
				   %%monitor = S#state.monitor,
                                  },
                    {reply, {ok, NS}, NewS}
            end
    end;

handle_call({add_nodes_check, Node, _PubType, {SGroupName, Nodes}}, _From, S) ->
    %%?debug({{add_nodes_check, Node, _PubType, {SGroupName, Nodes}}, _From, S}),
    NewConf = mk_new_s_group_conf(SGroupName, Nodes),
    application:set_env(kernel, s_groups, NewConf),
    NewSGroupNames = case lists:member(SGroupName, S#state.group_names) of
                        true -> S#state.group_names;
                        false -> lists:sort([SGroupName | S#state.group_names])
                    end,
    NewOwnSGroups = case lists:keyfind(SGroupName, 1, S#state.own_grps) of
                        false -> [{SGroupName, Nodes} | S#state.own_grps];
                        _ -> lists:keyreplace(SGroupName, 1, S#state.own_grps,
                                             {SGroupName, Nodes})
                    end,
    NewOtherSGroups = case lists:keyfind(SGroupName, 1, S#state.other_grps) of
    		          false -> S#state.other_grps;
			  _ -> lists:keydelete(SGroupName, 1, S#state.other_grps)
		      end,
    NoGroupNodes = global:get_known_s_group('no_group'),
    disconnect_nodes(NoGroupNodes),
    ?debug({"add_nodes_check_NoGroupNodes", NoGroupNodes}),
    NewS= S#state{sync_state = synced,
    	          group_names = NewSGroupNames,
    		  own_grps = NewOwnSGroups,
		  other_grps = NewOtherSGroups,
                  %%nodes = lists:usort(S#state.nodes ++ Nodes -- [node()]),
                  no_contact=lists:delete(Node, S#state.no_contact),
                  sync_error = lists:delete(Node, S#state.sync_error)
		  %%monitor = S#state.monitor
		  },
    {reply, agreed, NewS};


handle_call({s_group_state}, _From, S) ->
    NodeGrps = application:get_env(kernel, s_groups),
    OwnGrps = S#state.own_grps,
    {reply, {ok, NodeGrps, OwnGrps}, S};


%%%====================================================================================
%%% s_groups parameter changed
%%% The node is not resynced automatically because it would cause this node to
%%% be disconnected from those nodes not yet been upgraded.
%%%====================================================================================
handle_call({s_groups_changed, NewPara}, _From, S) ->
    %% Need to be changed because of the change of config_scan HL
    {NewGroupName, PubTpGrp, NewNodes, NewOther} = 
	case catch config_scan(NewPara, publish_type) of
	    {error, _Error2} ->
		exit({error, {'invalid s_groups definition', NewPara}});
	    {DefGroupName, PubType, DefNodes, DefOther} ->
		update_publish_nodes(S#state.publish_type, {PubType, DefNodes}),
		{DefGroupName, PubType, DefNodes, DefOther}
	end,

    %% #state.nodes is the common denominator of previous and new definition
    NN = NewNodes -- (NewNodes -- S#state.nodes),
    %% rest of the nodes in the new definition are marked as not yet contacted
    NNC = (NewNodes -- S#state.nodes) --  S#state.sync_error,
    %% remove sync_error nodes not belonging to the new group
    NSE = NewNodes -- (NewNodes -- S#state.sync_error),

    %% Disconnect the connection to nodes which are not in our old global group.
    %% This is done because if we already are aware of new nodes (to our global
    %% group) global is not going to be synced to these nodes. We disconnect instead
    %% of connect because upgrades can be done node by node and we cannot really
    %% know what nodes these new nodes are synced to. The operator can always 
    %% manually force a sync of the nodes after all nodes beeing uppgraded.
    %% We must disconnect also if some nodes to which we have a connection
    %% will not be in any global group at all.
    force_nodedown(nodes(connected) -- NewNodes),

    NewS = S#state{group_names = [NewGroupName], 
		   nodes = lists:sort(NN), 
		   no_contact = lists:sort(lists:delete(node(), NNC)), 
		   sync_error = lists:sort(NSE), 
		   other_grps = NewOther,
		   group_publish_type = PubTpGrp},
    {reply, ok, NewS};


%%%====================================================================================
%%% s_groups parameter added
%%% The node is not resynced automatically because it would cause this node to
%%% be disconnected from those nodes not yet been upgraded.
%%%====================================================================================
handle_call({s_groups_added, NewPara}, _From, S) ->
    %%io:format("### s_groups_changed, NewPara ~p ~n",[NewPara]),
    %% Need to be changed because of the change of config_scan!! HL
    {NewGroupName, PubTpGrp, NewNodes, NewOther} = 
	case catch config_scan(NewPara, publish_type) of
	    {error, _Error2} ->
		exit({error, {'invalid s_groups definition', NewPara}});
	    {DefGroupName, PubType, DefNodes, DefOther} ->
		update_publish_nodes(S#state.publish_type, {PubType, DefNodes}),
		{DefGroupName, PubType, DefNodes, DefOther}
	end,

    %% disconnect from those nodes which are not going to be in our global group
    force_nodedown(nodes(connected) -- NewNodes),

    %% Check which nodes are already updated
    OwnNG = get_own_nodes(),
    NGACArgs = case S#state.group_publish_type of
		   normal ->
		       [node(), OwnNG];
		   _ ->
		       [node(), S#state.group_publish_type, OwnNG]
	       end,
    {NN, NNC, NSE} = 
	lists:foldl(fun(Node, {NN_acc, NNC_acc, NSE_acc}) -> 
			    case rpc:call(Node, s_group, ng_add_check, NGACArgs) of
				{badrpc, _} ->
				    {NN_acc, [Node | NNC_acc], NSE_acc};
				agreed ->
				    {[Node | NN_acc], NNC_acc, NSE_acc};
				not_agreed ->
				    {NN_acc, NNC_acc, [Node | NSE_acc]}
			    end
		    end,
		    {[], [], []}, lists:delete(node(), NewNodes)),
    NewS = S#state{sync_state = synced, group_names = [NewGroupName], nodes = lists:sort(NN), 
		   sync_error = lists:sort(NSE), no_contact = lists:sort(NNC), 
		   other_grps = NewOther, group_publish_type = PubTpGrp},
    {reply, ok, NewS};


%%%====================================================================================
%%% s_groups parameter removed
%%%====================================================================================
handle_call({s_groups_removed, _NewPara}, _From, S) ->
    %%io:format("### s_groups_removed, NewPara ~p ~n",[_NewPara]),
    update_publish_nodes(S#state.publish_type),
    NewS = S#state{sync_state = no_conf, group_names = [], nodes = [], 
		   sync_error = [], no_contact = [], 
		   other_grps = []},
    {reply, ok, NewS};


%%%====================================================================================
%%% s_groups parameter added to some other node which thinks that we
%%% belong to the same global group.
%%% It could happen that our node is not yet updated with the new node_group parameter
%%%====================================================================================
handle_call({ng_add_check, Node, PubType, OthersNG}, _From, S) ->
    %% Check which nodes are already updated
    erlang:diaplay("TTTTTTTTTTTTTTTTTTTTTTTTTTTTT\n"),
    OwnNG = get_own_nodes(),
    case S#state.group_publish_type =:= PubType of
	true ->
	    case OwnNG of
		OthersNG ->
		    NN = [Node | S#state.nodes],
		    NSE = lists:delete(Node, S#state.sync_error),
		    NNC = lists:delete(Node, S#state.no_contact),
		    NewS = S#state{nodes = lists:sort(NN), 
				   sync_error = NSE, 
				   no_contact = NNC},
		    {reply, agreed, NewS};
		_ ->
		    {reply, not_agreed, S}
	    end;
	_ ->
	    {reply, not_agreed, S}
    end;



%%%====================================================================================
%%% Misceleaneous help function to read some variables
%%%====================================================================================
handle_call(info, _From, S) ->    
    Reply = [{state,            S#state.sync_state},
	     {own_group_names,  S#state.group_names},
	     {own_group_nodes,  get_own_nodes()},
	     {synced_nodes,     S#state.nodes},
	     {sync_error,       S#state.sync_error},
	     {no_contact,       S#state.no_contact},
             {own_s_groups,     S#state.own_grps},
	     {other_groups,     S#state.other_grps},
	     {monitoring,       S#state.monitor}],
    {reply, Reply, S};

handle_call(get, _From, S) ->
    {reply, get(), S};


%%%====================================================================================
%%% Only for test suites. These tests when the search process exits.
%%%====================================================================================
handle_call({registered_names_test, {node, 'test3844zty'}}, From, S) ->
    Pid = global_search:start(names_test, {node, 'test3844zty'}),
    Wait = get(registered_names),
    put(registered_names, [{Pid, From} | Wait]),
    {noreply, S};
handle_call({registered_names_test, {node, _Node}}, _From, S) ->
    {reply, {error, illegal_function_call}, S};
handle_call({send_test, Name, 'test3844zty'}, From, S) ->
    Pid = global_search:start(send_test, 'test3844zty'),
    Wait = get(send),
    put(send, [{Pid, From, Name, 'test3844zty'} | Wait]),
    {noreply, S};
handle_call({send_test, _Name, _Msg }, _From, S) ->
    {reply, {error, illegal_function_call}, S};
handle_call({whereis_name_test, 'test3844zty'}, From, S) ->
    Pid = global_search:start(whereis_test, 'test3844zty'),
    Wait = get(whereis_name),
    put(whereis_name, [{Pid, From} | Wait]),
    {noreply, S};
handle_call({whereis_name_test, _Name}, _From, S) ->
    {reply, {error, illegal_function_call}, S};

handle_call(Call, _From, S) ->
     %%io:format("***** handle_call ~p~n",[Call]),
    {reply, {illegal_message, Call}, S}.





%%%====================================================================================
%%% registered_names({node, Node}) -> [Name] | {error, ErrorMessage}
%%% registered_names({s_group, SGroupName}) -> [Name] | {error, ErrorMessage}
%%%
%%% Get a list of nodes in the own global group
%%%====================================================================================
handle_cast({registered_names, User}, S) ->
    Res = global:registered_names(all_names),
    User ! {registered_names_res, Res},
    {noreply, S};

handle_cast({registered_names_res, SGroupName, Result1, Pid, From}, S) ->
    case SGroupName of
    	 undefined ->
	    Result = Result1;
	 _ ->
	    Result = s_group_names(Result1, [], SGroupName)
    end,
    unlink(Pid),
    exit(Pid, normal),
    Wait = get(registered_names),
    NewWait = lists:delete({Pid, From},Wait),
    put(registered_names, NewWait),
    gen_server:reply(From, Result),
    {noreply, S};


%%%====================================================================================
%%% send(Name, SGroupName, Msg) -> Pid | {error, ErrorMessage}
%%% send(Node, Name, SGroupName, Msg) -> Pid | {error, ErrorMessage}
%%%
%%% The registered Name is found; send the message to it, kill the search process,
%%% and return to the requesting process.
%%%====================================================================================
handle_cast({send_res, Result, Name, SGroupName, Msg, Pid, From}, S) ->	%NC
    case Result of
	{badarg,{Name, SGroupName, Msg}} ->
	    continue;
	ToPid ->
	    ToPid ! Msg
    end,
    unlink(Pid),
    exit(Pid, normal),
    Wait = get(send),
    NewWait = lists:delete({Pid, From, Name, SGroupName, Msg},Wait),
    put(send, NewWait),
    gen_server:reply(From, Result),
    {noreply, S};



%%%====================================================================================
%%% A request from a search process to check if this Name is registered at this node.
%%%====================================================================================
handle_cast({find_name, User, Name}, S) ->	%NC?
    Res = global:whereis_name(Name),
    User ! {find_name_res, Res},
    {noreply, S};

handle_cast({find_name, User, Name, SGroupName}, S) ->	%NC
    Res = global:whereis_name(Name, SGroupName),
    User ! {find_name_res, Res},
    {noreply, S};
%%%====================================================================================
%%% whereis_name(Name, SGroupName) -> Pid | undefined
%%% whereis_name(Node, Name, SGroupName) -> Pid | undefined
%%%
%%% The registered Name is found; kill the search process
%%% and return to the requesting process.
%%%====================================================================================
handle_cast({find_name_res, Result, Pid, From}, S) ->
    unlink(Pid),
    exit(Pid, normal),
    Wait = get(whereis_name),
    NewWait = lists:delete({Pid, From},Wait),
    put(whereis_name, NewWait),
    gen_server:reply(From, Result),
    {noreply, S};


%%%====================================================================================
%%% The node is synced successfully
%%%====================================================================================
handle_cast({synced, NoContact}, S) ->
    %io:format("~p>>>>> synced ~p  ~n",[node(), NoContact]),
    kill_s_group_check(),
    Nodes = get_own_nodes() -- [node() | NoContact],
    {noreply, S#state{nodes = lists:sort(Nodes),
		      sync_error = [],
		      no_contact = NoContact}};    


%%%====================================================================================
%%% The node could not sync with some other nodes.
%%%====================================================================================
handle_cast({sync_error, NoContact, ErrorNodes}, S) ->
    Txt = io_lib:format("Global group: Could not synchronize with these nodes ~p~n"
			"because s_groups were not in agreement. ~n", [ErrorNodes]),
    error_logger:error_report(Txt),
    %%?debug(lists:flatten(Txt)),
    kill_s_group_check(),
    Nodes = (get_own_nodes() -- [node() | NoContact]) -- ErrorNodes,
    {noreply, S#state{nodes = lists:sort(Nodes), 
		      sync_error = ErrorNodes,
		      no_contact = NoContact}};


%%%====================================================================================
%%% Another node is checking this node's group configuration
%%%====================================================================================
handle_cast({conf_check, Vsn, Node, From, sync, CmnGroups, CmnGroupNodes}, S) ->
    ?debug({"s_group_handle_conf_check", Vsn, Node, From, sync, CmnGroups, CmnGroupNodes}),
    handle_cast({conf_check, Vsn, Node, From, sync, CmnGroups, normal, CmnGroupNodes}, S);

handle_cast({conf_check, Vsn, Node, From, sync, CmnGroups, PubType, CmnGroupNodes}, S) ->
    ?debug({"s_group_handle_conf_check", Vsn, Node, From, sync, CmnGroups, PubType, CmnGroupNodes}),
    CurNodes = S#state.nodes,
    ?debug({"s_group_handle_conf_check_CurNodes", CurNodes}),
    %% Another node is syncing, 
    %% done for instance after upgrade of s_group parameters
    NS = 
	case application:get_env(kernel, s_groups) of
	    undefined ->
		%% The current node doesn't an s_group definition
		update_publish_nodes(S#state.publish_type),
		disconnect_nodes([Node]),
		{s_group_check, Node} ! {config_error, Vsn, From, node()},
		S;
	    {ok, []} ->
		%% The current node s_group definition is empty
		update_publish_nodes(S#state.publish_type),
		disconnect_nodes([Node]),
		{s_group_check, Node} ! {config_error, Vsn, From, node()},
		S;
	    %%---------------------------------
	    %% s_groups are defined
	    %%---------------------------------
	    {ok, GroupNodes} ->
                case config_scan(GroupNodes, publish_type) of
		    {error, _Error2} ->
			%% The current node s_group definition is faulty
			disconnect_nodes([Node]),
			{s_group_check, Node} ! {config_error, Vsn, From, node()},
			S#state{nodes = lists:delete(Node, CurNodes)};
                    {ok, OwnSGroups, _OtherSGroups} ->
		        %% OwnSGroups::[{SGroupName, PubType, Nodes}]
                        ?debug({"s_group_handle_conf_check_CmnGroups_OwnSGroups",
				                   CmnGroups, OwnSGroups}),
			{OwnCmnGroups, S1} =
			    handle_conf_check(CmnGroups, [], OwnSGroups, Node, CurNodes, S),
			%% OwnCmnGroups::[GroupName]
			case OwnCmnGroups of
                            [] ->
                                %% node_group definitions were not in agreement
                  		disconnect_nodes([Node]),
                  		{s_group_check, Node} ! {config_error, Vsn, From, node()},
                  		NN = lists:delete(Node, S1#state.nodes),
                  		NSE = lists:delete(Node, S1#state.sync_error),
                  		NNC = lists:delete(Node, S1#state.no_contact),
                  		S1#state{nodes = NN,
                          	         sync_error = NSE,
                          		 no_contact = NNC};
			    _ ->
			        ?debug({"s_group_handle_conf_check_OwnCmnGroups_Node",
				                           OwnCmnGroups, Node}), 
                		global_name_server ! {nodeup_s, OwnCmnGroups, Node},
                  		{s_group_check, Node} !
				       {config_s_ok, Vsn, From, OwnCmnGroups, node()},
				S1
                        end
                end
        end,
    {noreply, NS};

handle_cast(_Cast, S) ->
%    io:format("***** handle_cast ~p~n",[_Cast]),
    {noreply, S}.
    


%%%====================================================================================
%%% A node went down. If no global group configuration inform global;
%%% if global group configuration inform global only if the node is one in
%%% the own global group.
%%%====================================================================================
handle_info({nodeup, Node}, S) when S#state.sync_state =:= no_conf ->
    case application:get_env(kernel, s_groups) of 
        undefined ->
            %%io:format("~p>>>>> nodeup, Node ~p ~n",[node(), Node]),
            ?debug({"NodeUp:", node(), Node}),
            send_monitor(S#state.monitor, {nodeup, Node}, S#state.sync_state),
	    ?debug({"S", S}),
            global_name_server ! {nodeup, no_group, Node},
            {noreply, S};
        _ ->
         handle_node_up(Node,S)
    end;            
handle_info({nodeup, Node}, S) ->
    %% io:format("~p>>>>> nodeup, Node ~p ~n",[node(), Node]),
    %%?debug({"NodeUp:",  node(), Node}),
    handle_node_up(Node, S);
%%%====================================================================================
%%% A node has crashed. 
%%% nodedown must always be sent to global; this is a security measurement
%%% because during release upgrade the s_groups parameter is upgraded
%%% before the node is synced. This means that nodedown may arrive from a
%%% node which we are not aware of.
%%%====================================================================================
handle_info({nodedown, Node}, S) when S#state.sync_state =:= no_conf ->
%    io:format("~p>>>>> nodedown, no_conf Node ~p~n",[node(), Node]),
    send_monitor(S#state.monitor, {nodedown, Node}, S#state.sync_state),
    global_name_server ! {nodedown, Node},
    {noreply, S};
handle_info({nodedown, Node}, S) ->
%    io:format("~p>>>>> nodedown, Node ~p  ~n",[node(), Node]),
    send_monitor(S#state.monitor, {nodedown, Node}, S#state.sync_state),
    global_name_server ! {nodedown, Node},
    NN = lists:delete(Node, S#state.nodes),
    NSE = lists:delete(Node, S#state.sync_error),
    NNC = case {lists:member(Node, get_own_nodes()), 
		lists:member(Node, S#state.no_contact)} of
	      {true, false} ->
		  [Node | S#state.no_contact];
	      _ ->
		  S#state.no_contact
	  end,
    {noreply, S#state{nodes = NN, no_contact = NNC, sync_error = NSE}};


%%%====================================================================================
%%% A node has changed its s_groups definition, and is telling us that we are not
%%% included in his group any more. This could happen at release upgrade.
%%%====================================================================================
handle_info({disconnect_node, Node}, S) ->
%    io:format("~p>>>>> disconnect_node Node ~p CN ~p~n",[node(), Node, S#state.nodes]),
    case {S#state.sync_state, lists:member(Node, S#state.nodes)} of
	{synced, true} ->
	    send_monitor(S#state.monitor, {nodedown, Node}, S#state.sync_state);
	_ ->
	    cont
    end,
    global_name_server ! {nodedown, Node}, %% nodedown is used to inform global of the
                                           %% disconnected node
    NN = lists:delete(Node, S#state.nodes),
    NNC = lists:delete(Node, S#state.no_contact),
    NSE = lists:delete(Node, S#state.sync_error),
    {noreply, S#state{nodes = NN, no_contact = NNC, sync_error = NSE}};




handle_info({'EXIT', ExitPid, Reason}, S) ->
    check_exit(ExitPid, Reason),
    {noreply, S};


handle_info(_Info, S) ->
%    io:format("***** handle_info = ~p~n",[_Info]),
    {noreply, S}.

handle_node_up(Node, S) ->
    OthersNG = case S#state.sync_state==no_conf andalso 
                   application:get_env(kernel, s_groups)==undefined of 
                   true -> 
                       [];
                   false ->
                       X = (catch rpc:call(Node, s_group, get_own_s_groups_with_nodes, [])),
		       case X of
			   X when is_list(X) ->
			       X;
			   _ ->
			       []
		       end
               end,
    %%?debug({"OthersNG:",OthersNG}),
    OwnNGs = get_own_s_groups_with_nodes(),
    OwnGroups = element(1, lists:unzip(OwnNGs)),
    %%?debug({"ownsNG:",OwnNGs}),
    NNC = lists:delete(Node, S#state.no_contact),
    NSE = lists:delete(Node, S#state.sync_error),
    case shared_s_groups_match(OwnNGs, OthersNG) of 
        true->
            OthersGroups = element(1, lists:unzip(OthersNG)),
            CommonGroups = intersection(OwnGroups, OthersGroups),
            send_monitor(S#state.monitor, {nodeup, Node}, S#state.sync_state),
            ?debug({s_group_nodeup_handle_node_up, OwnGroups, Node, CommonGroups}),
	    [global_name_server ! {nodeup, Group, Node}||Group<-CommonGroups],  
	    case lists:member(Node, S#state.nodes) of
		false ->
		    NN = lists:sort([Node | S#state.nodes]),
		    {noreply, S#state{
                                sync_state=synced,
                                group_names = OwnGroups,
                                nodes = NN, 
                                no_contact = NNC,
                                sync_error = NSE}};
		true ->
		    {noreply, S#state{
                                sync_state=synced,
                                group_names = OwnGroups,
                                no_contact = NNC,
                                sync_error = NSE}}
	    end;
	false ->
            case {lists:member(Node, get_own_nodes()), 
		  lists:member(Node, S#state.sync_error)} of
		{true, false} ->
		    NSE2 = lists:sort([Node | S#state.sync_error]),
		    {noreply, S#state{
                                sync_state = synced,
                                group_names = OwnGroups,
                                no_contact = NNC,
                                sync_error = NSE2}};
                _ ->
                    {noreply, S#state{sync_state=synced,
                                      group_names = OwnGroups}}
	    end
    end.



shared_s_groups_match(OwnSGroups, OthersSGroups) ->
    OwnSGroupNames = [G||{G, _Nodes}<-OwnSGroups],
    OthersSGroupNames = [G||{G, _Nodes}<-OthersSGroups],
    SharedSGroups = intersection(OwnSGroupNames, OthersSGroupNames),
    case SharedSGroups of 
        [] -> false;
        Gs ->
            Own =[{G, lists:sort(Nodes)}
                  ||{G, Nodes}<-OwnSGroups, lists:member(G, Gs)],
            Others= [{G, lists:sort(Nodes)}
                     ||{G, Nodes}<-OthersSGroups, lists:member(G, Gs)],
            lists:sort(Own) == lists:sort(Others)
    end.
intersection(_, []) -> 
    [];
intersection(L1, L2) ->
    L1 -- (L1 -- L2).


terminate(_Reason, _S) ->
    ok.
    

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.





%%%====================================================================================
%%% Check the global group configuration.
%%%====================================================================================

%% type spec added by HL.
-spec config_scan(NodeGrps::[group_tuple()])->
                         {ok, OwnGrps::[{group_name(), [node()]}], 
                          OtherGrps::[{group_name(), [node()]}]}
                             |{error, any()}.

%% Functionality rewritten by HL.
config_scan(NodeGrps) ->
    config_scan(NodeGrps, original).

config_scan(NodeGrps, original) ->
     config_scan(NodeGrps, publish_type);

config_scan(NodeGrps, publish_type) ->
    config_scan(node(), NodeGrps, [], []).

config_scan(_MyNode, [], MyOwnNodeGrps, OtherNodeGrps) ->
    {ok, MyOwnNodeGrps, OtherNodeGrps};
config_scan(MyNode, [GrpTuple|NodeGrps], MyOwnNodeGrps, OtherNodeGrps) ->
    {GrpName, PubTypeGroup, Nodes} = grp_tuple(GrpTuple),
    case lists:member(MyNode, Nodes) of
	true ->
            %% HL: is PubTypeGroup needed?
            config_scan(MyNode, NodeGrps, 
                        [{GrpName, PubTypeGroup,lists:sort(Nodes)}
                         |MyOwnNodeGrps], 
                        OtherNodeGrps);
	false ->
	    config_scan(MyNode,NodeGrps, MyOwnNodeGrps,
                        [{GrpName, lists:sort(Nodes)}|
                         OtherNodeGrps])
    end.

grp_tuple({Name, Nodes}) ->
    {Name, normal, Nodes};
%grp_tuple({Name, hidden, Nodes}) ->
%    {Name, hidden, Nodes};
grp_tuple({Name, normal, Nodes}) ->
    {Name, normal, Nodes}.

    
%% config_scan(NodeGrps) ->
%%     config_scan(NodeGrps, original).

%% config_scan(NodeGrps, original) ->
%%     case config_scan(NodeGrps, publish_type) of
%% 	{DefGroupName, _, DefNodes, DefOther} ->
%% 	    {DefGroupName, DefNodes, DefOther};
%% 	Error ->
%% 	    Error
%%     end;
%% config_scan(NodeGrps, publish_type) ->
%%     config_scan(node(), normal, NodeGrps, no_name, [], []).

%% config_scan(_MyNode, PubType, [], Own_name, OwnNodes, OtherNodeGrps) ->
%%     {Own_name, PubType, lists:sort(OwnNodes), lists:reverse(OtherNodeGrps)};
%% config_scan(MyNode, PubType, [GrpTuple|NodeGrps], Own_name, OwnNodes, OtherNodeGrps) ->
%%     {Name, PubTypeGroup, Nodes} = grp_tuple(GrpTuple),
%%     case lists:member(MyNode, Nodes) of
%% 	true ->
%% 	    case Own_name of
%% 		no_name ->
%% 		    config_scan(MyNode, PubTypeGroup, NodeGrps, Name, Nodes, OtherNodeGrps);
%% 		_ ->
%% 		    {error, {'node defined twice', {Own_name, Name}}}
%% 	    end;
%% 	false ->
%% 	    config_scan(MyNode,PubType,NodeGrps,Own_name,OwnNodes,
%% 			[{Name, Nodes}|OtherNodeGrps])
%%     end.

    
%%%====================================================================================
%%% The special process which checks that all nodes in the own global group
%%% agrees on the configuration.
%%%====================================================================================
-spec sync_init(_, _, _, _) -> no_return().
sync_init(Type, _Cname, PubType, SGroupNodesPairs) ->
    ?debug({"sync_int:", Type, _Cname, PubType, SGroupNodesPairs}),
    NodeGroupPairs = ng_pairs(SGroupNodesPairs),
    ?debug({"sync_init_NodeGroupPairs", NodeGroupPairs}),
    Nodes = lists:usort(element(1,lists:unzip(NodeGroupPairs))),
    ?debug({"sync_init_node()_Nodes:", node(), Nodes}),
    {Up, Down} = sync_check_node(lists:delete(node(), Nodes), [], []),
    ?debug({"sync_init_Up_Down:", Up, Down}),
    sync_check_init(Type, Up, NodeGroupPairs, Down, PubType).

sync_check_node([], Up, Down) ->
    {Up, Down};
sync_check_node([Node|Nodes], Up, Down) ->
    case net_adm:ping(Node) of
	pang ->
	    sync_check_node(Nodes, Up, [Node|Down]);
	pong ->
	    sync_check_node(Nodes, [Node|Up], Down)
    end.


%%%-----------------------------------------------------------
%%% Converts GroupTup = [{GroupName, Nodes}] in
%%% NodeGroupPairs = [{Node, GroupNames}]
%%%-----------------------------------------------------------
ng_pairs(GroupTup) ->
    NGPairs = lists:append([[{Node, GroupName} || Node<-Nodes]
    	      		     || {GroupName, Nodes} <- GroupTup]),
    ng_pairs(NGPairs, []).

ng_pairs([], NodeTup) ->
    NodeTup;
ng_pairs([{Node, GroupName} | RemPairs], NodeTup) ->
    NewNodeTup = case lists:keyfind(Node, 1, NodeTup) of
        false ->
	      [{Node, [GroupName]} | NodeTup];
	{Node, GroupNames} ->
	      lists:keyreplace(Node, 1, NodeTup, {Node, [GroupName | GroupNames]})
    end,
    ng_pairs(RemPairs, NewNodeTup).


%%%-------------------------------------------------------------
%%% Check that all nodes are in agreement of the s_group
%%% configuration.
%%%-------------------------------------------------------------
-spec sync_check_init(_, _, _, _, _) -> no_return().
sync_check_init(Type, Up, NodeGroupPairs, Down, PubType) ->
    sync_check_init(Type, Up, NodeGroupPairs, 3, [], Down, PubType).

-spec sync_check_init(_, _, _, _, _, _,  _) -> no_return().
sync_check_init(_Type, NoContact, _NodeGroupPairss, 0,
                ErrorNodes, Down, _PubType) ->
    case ErrorNodes of
	[] -> 
	    gen_server:cast(?MODULE, {synced, lists:sort(NoContact ++ Down)});
	_ ->
	    gen_server:cast(?MODULE, {sync_error, lists:sort(NoContact ++ Down),
					   ErrorNodes})
    end,
    receive
	kill ->
	    exit(normal)
    after 5000 ->
	    exit(normal)
    end;

sync_check_init(Type, Up, NodeGroupPairs, N, ErrorNodes, Down, PubType) ->
    ?debug({"sync_check_init_Type_Up_NodeGroupPairs_N_ErrorNodes_Down_PubType",
                      Type, Up, NodeGroupPairs, N, ErrorNodes, Down, PubType}),
    lists:foreach(fun(Node) ->
                          {Node, Groups} = lists:keyfind(Node, 1, NodeGroupPairs),
                          GroupNodes = gn_pairs(Node, NodeGroupPairs),
                          ConfCheckMsg = 
                              case PubType of
                                  normal ->
                                      {conf_check, ?cc_vsn, node(), self(), Type, 
                                       Groups, GroupNodes};
                                  _ ->
                                      {conf_check, ?cc_vsn, node(), self(), Type,
                                       Groups, PubType, GroupNodes}
                              end,
                          ?debug({sync_check_init_conf_check, Node, ConfCheckMsg}),
                          gen_server:cast({?MODULE, Node}, ConfCheckMsg)
		  end, Up),
    case sync_check(Up) of
	{ok, synced} ->
	    sync_check_init(Type, [], NodeGroupPairs, 0,
                            ErrorNodes, Down, PubType);
	{error, NewErrorNodes} ->
	    sync_check_init(Type, [], NodeGroupPairs, 0,
                            ErrorNodes ++ NewErrorNodes, Down, PubType);
	{more, Rem, NewErrorNodes} ->
	    %% Try again to reach the s_group, 
	    %% obviously the node is up but not the s_group process.
	    sync_check_init(Type, Rem, NodeGroupPairs, N - 1,
                            ErrorNodes ++ NewErrorNodes, Down, PubType)
    end.

gn_pairs(Node, NodeGroupPairs) ->
	{Node, Groups} = lists:keyfind(Node, 1, NodeGroupPairs),
	InitGroupNodePairs = [{G, [Node]} || G <- Groups],
	NodeGroupPairs1 = lists:delete({Node, Groups}, NodeGroupPairs),
	%% RemNodes brake into pairs {Node, Group}
	NodeGroupList = ng_list(NodeGroupPairs1, []),
	gn_pairs_do(InitGroupNodePairs, NodeGroupList, []).

ng_list([], NodeGroupList) ->
	NodeGroupList;
ng_list([{Node, Groups} | NodeGroupPairs], NodeGroupList) ->
	NewNodeGroupList = [{Node, G} || G <- Groups],
	ng_list(NodeGroupPairs, NodeGroupList++NewNodeGroupList).

gn_pairs_do([], _NodeGroupPairs, GroupNodePairs) ->
	lists:sort(GroupNodePairs);
gn_pairs_do([{Group, Node} | InitGroupNodePairs], NodeGroupPairs, GroupNodePairs) ->
	Nodes1 = [Node1 || {Node1, G} <- NodeGroupPairs, G==Group],
	NewNodes = lists:sort(Node ++ Nodes1),
	gn_pairs_do(InitGroupNodePairs, NodeGroupPairs, [{Group, NewNodes} | GroupNodePairs]).


handle_conf_check([], OwnCmnGroups, _OwnSGroups, _Node, _CurNodes, S) ->
    {OwnCmnGroups, S};
handle_conf_check([CmnGroup | CmnGroups], OwnCmnGroups, OwnSGroups, Node, CurNodes, S) ->
    case lists:keyfind(CmnGroup, 1, OwnSGroups) of
        {CmnGroup, PubType, CmnNodes} ->
	     S1 = handle_conf_check1(PubType, CmnNodes, Node, CurNodes, S),
    	     handle_conf_check(CmnGroups, [CmnGroup | OwnCmnGroups],
	                       OwnSGroups, Node, CurNodes, S1);
	_ ->
             handle_conf_check(CmnGroups, OwnCmnGroups, OwnSGroups, Node, CurNodes, S)
    end.

handle_conf_check1(PubType, CmnNodes, Node, CurNodes, S) ->
    %% Add Node to the #state.nodes if it isn't there
    update_publish_nodes(S#state.publish_type, {PubType, CmnNodes}),
    case lists:member(Node, CurNodes) of
        false ->
              NewNodes = lists:sort([Node | CurNodes]),
              NSE = lists:delete(Node, S#state.sync_error),
              NNC = lists:delete(Node, S#state.no_contact),
              S#state{nodes = NewNodes, 
                      sync_error = NSE,
                      no_contact = NNC};
        true ->
              S
    end.
 

sync_check(Up) ->
    sync_check(Up, Up, []).

sync_check([], _Up, []) ->
    {ok, synced};
sync_check([], _Up, ErrorNodes) ->
    {error, ErrorNodes};
sync_check(Rem, Up, ErrorNodes) ->
    receive
	{config_ok, ?cc_vsn, Pid, GroupName, Node} when Pid =:= self() ->
	    global_name_server ! {nodeup, GroupName, Node},
	    ?debug({"s_group_nodeup_sync_check", nodeup, GroupName, Node}),
	    sync_check(Rem -- [Node], Up, ErrorNodes);
	{config_s_ok, ?cc_vsn, Pid, CmnGroups, Node} when Pid =:= self() ->
	    global_name_server ! {nodeup_s, CmnGroups, Node},
	    ?debug({"s_group_nodeup_sync_check_s", CmnGroups, Node}),
	    sync_check(Rem -- [Node], Up, ErrorNodes);
	{config_error, ?cc_vsn, Pid, Node} when Pid =:= self() ->
	    sync_check(Rem -- [Node], Up, [Node | ErrorNodes]);
	{no_s_group_configuration, ?cc_vsn, Pid, Node} when Pid =:= self() ->
	    sync_check(Rem -- [Node], Up, [Node | ErrorNodes]);
	%% Ignore, illegal vsn or illegal Pid
	_ ->
	    sync_check(Rem, Up, ErrorNodes)
    after 2000 ->
	    %% Try again, the previous conf_check message  
	    %% apparently disapared in the magic black hole.
	    {more, Rem, ErrorNodes}
    end.


%%%====================================================================================
%%% A process wants to toggle monitoring nodeup/nodedown from nodes.
%%%====================================================================================
monitor_nodes(true, Pid, State) ->
    link(Pid),
    Monitor = State#state.monitor,
    {ok, State#state{monitor = [Pid|Monitor]}};
monitor_nodes(false, Pid, State) ->
    Monitor = State#state.monitor,
    State1 = State#state{monitor = delete_all(Pid,Monitor)},
    do_unlink(Pid, State1),
    {ok, State1};
monitor_nodes(_, _, State) ->
    {error, State}.

delete_all(From, [From |Tail]) -> delete_all(From, Tail);
delete_all(From, [H|Tail]) ->  [H|delete_all(From, Tail)];
delete_all(_, []) -> [].

%% do unlink if we have no more references to Pid.
do_unlink(Pid, State) ->
    case lists:member(Pid, State#state.monitor) of
	true ->
	    false;
	_ ->
%	    io:format("unlink(Pid) ~p~n",[Pid]),
	    unlink(Pid)
    end.



%%%====================================================================================
%%% Send a nodeup/down messages to monitoring Pids in the own global group.
%%%====================================================================================
send_monitor([P|T], M, no_conf) -> safesend_nc(P, M), send_monitor(T, M, no_conf);
send_monitor([P|T], M, SyncState) -> safesend(P, M), send_monitor(T, M, SyncState);
send_monitor([], _, _) -> ok.

safesend(Name, {Msg, Node}) when is_atom(Name) ->
    case lists:member(Node, get_own_nodes()) of
	true ->
	    case whereis(Name) of 
		undefined ->
		    {Msg, Node};
		P when is_pid(P) ->
		    P ! {Msg, Node}
	    end;
	false ->
	    not_own_group
    end;
safesend(Pid, {Msg, Node}) -> 
    case lists:member(Node, get_own_nodes()) of
	true ->
	    Pid ! {Msg, Node};
	false ->
	    not_own_group
    end.

safesend_nc(Name, {Msg, Node}) when is_atom(Name) ->
    case whereis(Name) of 
	undefined ->
	    {Msg, Node};
	P when is_pid(P) ->
	    P ! {Msg, Node}
    end;
safesend_nc(Pid, {Msg, Node}) -> 
    Pid ! {Msg, Node}.






%%%====================================================================================
%%% Check which user is associated to the crashed process.
%%%====================================================================================
check_exit(ExitPid, Reason) ->
%    io:format("===EXIT===  ~p ~p ~n~p   ~n~p   ~n~p ~n~n",[ExitPid, Reason, get(registered_names), get(send), get(whereis_name)]),
    check_exit_reg(get(registered_names), ExitPid, Reason),
    check_exit_send(get(send), ExitPid, Reason),
    check_exit_where(get(whereis_name), ExitPid, Reason).


check_exit_reg(undefined, _ExitPid, _Reason) ->
    ok;
check_exit_reg(Reg, ExitPid, Reason) ->
    case lists:keysearch(ExitPid, 1, lists:delete(undefined, Reg)) of
	{value, {ExitPid, From}} ->
	    NewReg = lists:delete({ExitPid, From}, Reg),
	    put(registered_names, NewReg),
	    gen_server:reply(From, {error, Reason});
	false ->
	    not_found_ignored
    end.


check_exit_send(undefined, _ExitPid, _Reason) ->
    ok;
check_exit_send(Send, ExitPid, _Reason) ->
    case lists:keysearch(ExitPid, 1, lists:delete(undefined, Send)) of
	{value, {ExitPid, From, Name, Msg}} ->
	    NewSend = lists:delete({ExitPid, From, Name, Msg}, Send),
	    put(send, NewSend),
	    gen_server:reply(From, {badarg, {Name, Msg}});
	false ->
	    not_found_ignored
    end.


check_exit_where(undefined, _ExitPid, _Reason) ->
    ok;
check_exit_where(Where, ExitPid, Reason) ->
    case lists:keysearch(ExitPid, 1, lists:delete(undefined, Where)) of
	{value, {ExitPid, From}} ->
	    NewWhere = lists:delete({ExitPid, From}, Where),
	    put(whereis_name, NewWhere),
	    gen_server:reply(From, {error, Reason});
	false ->
	    not_found_ignored
    end.



%%%====================================================================================
%%% Kill any possible s_group_check processes
%%%====================================================================================
kill_s_group_check() ->
    case whereis(s_group_check) of
	undefined ->
	    ok;
	Pid ->
	    unlink(Pid),
	    s_group_check ! kill,
	    unregister(s_group_check)
    end.


%%%====================================================================================
%%% Disconnect nodes not belonging to own s_groups
%%%====================================================================================
disconnect_nodes(DisconnectNodes) ->
    lists:foreach(fun(Node) ->
			  {s_group, Node} ! {disconnect_node, node()},
			  global:node_disconnected(Node)
		  end,
		  DisconnectNodes).


%%%====================================================================================
%%% Disconnect nodes not belonging to own s_groups
%%%====================================================================================
force_nodedown(DisconnectNodes) ->
    lists:foreach(fun(Node) ->
			  erlang:disconnect_node(Node),
			  global:node_disconnected(Node)
		  end,
		  DisconnectNodes).


%%%====================================================================================
%%% Get the current s_groups definition
%%%====================================================================================
get_own_nodes_with_errors() ->
    case application:get_env(kernel, s_groups) of
	undefined ->
	    {ok, all};
	{ok, []} ->
	    {ok, all};
	{ok, NodeGrps} ->
            case catch config_scan(NodeGrps, publish_type) of
		{error, Error} ->
		    {error, Error};
                {ok, OwnSGroups, _} ->
                    Nodes = lists:append([Nodes||{_, _, Nodes}<-OwnSGroups]),
                    {ok, lists:usort(Nodes)}
            end
	    end.

get_own_nodes() ->
    case get_own_nodes_with_errors() of
	{ok, all} ->
	    [];
	{error, _} ->
	    [];
	{ok, Nodes} ->
	    Nodes
    end.


get_own_s_groups_with_nodes() ->
    case application:get_env(kernel, s_groups) of
	undefined ->
	    [];
	{ok, []} ->
	    [];
	{ok, NodeGrps} ->
            case catch config_scan(NodeGrps, publish_type) of
                {error,_Error} ->
                    [];
                {ok, OwnSGroups, _} ->
                    [{Group, Nodes} || {Group, _PubType, Nodes} <- OwnSGroups]
            end
    end.
%%%====================================================================================
%%% -hidden command line argument
%%%====================================================================================
publish_arg() ->
     normal.
%    case init:get_argument(hidden) of
%	{ok,[[]]} ->
%	    hidden;
%	{ok,[["true"]]} ->
%	    hidden;
%	_ ->
%	    normal
%    end.


%%%====================================================================================
%%% Own group publication type and nodes
%%%====================================================================================
own_group() ->
    case application:get_env(kernel, s_groups) of
	undefined ->
	    no_group;
	{ok, []} ->
	    no_group;
	{ok, NodeGrps} ->
	    case catch config_scan(NodeGrps, publish_type) of
		{error, _} ->
		    no_group;
                {ok, OwnSGroups, _OtherSGroups} ->
                    NodesDef = lists:append([Nodes||{_, _, Nodes}<-OwnSGroups]),
		    ?debug({"own_group_NodesDef", NodesDef}),
                    {normal, NodesDef}
            end
    end.
 

%%%====================================================================================
%%% Help function which computes publication list
%%%====================================================================================
publish_on_nodes(normal, no_group) ->
    all;
publish_on_nodes(hidden, no_group) ->
    [];
publish_on_nodes(_, {_, Nodes}) ->
    Nodes.
%publish_on_nodes(normal, {normal, _}) ->
%    all;
%publish_on_nodes(hidden, {_, Nodes}) ->
%    Nodes;
%publish_on_nodes(_, {hidden, Nodes}) ->
%    Nodes.

%%%====================================================================================
%%% Update net_kernels publication list
%%%====================================================================================
update_publish_nodes(PubArg) ->
    update_publish_nodes(PubArg, no_group).
update_publish_nodes(PubArg, MyGroup) ->
    net_kernel:update_publish_nodes(publish_on_nodes(PubArg, MyGroup)).


%%%====================================================================================
%%% Fetch publication list
%%%====================================================================================
publish_on_nodes() ->
    publish_on_nodes(publish_arg(), own_group()).



%% assume this is no s_group name conflict. HL.
-spec mk_new_s_group_conf(SGroupName, Nodes) -> [{SGroupName, Nodes}] when
      SGroupName :: group_name(),
      Nodes :: [Node :: node()].

mk_new_s_group_conf(SGroupName, Nodes0) ->
    Nodes = lists:sort(Nodes0),
    case application:get_env(kernel, s_groups) of
        undefined ->
            [{SGroupName, Nodes}];
        {ok, []} ->
             [{SGroupName, Nodes}];
        {ok, NodeSGroups} ->
            case lists:keyfind(SGroupName, 1, NodeSGroups) of 
                false ->
                    [{SGroupName, Nodes} | NodeSGroups];
                _ ->
                    lists:keyreplace(SGroupName, 1, NodeSGroups, {SGroupName, Nodes})
            end
    end.


rm_s_group_from_conf(SGroupName) ->
    case application:get_env(kernel, s_groups) of
        undefined ->
            [];
        {ok, []} ->
            [];
        {ok, NodeSGroups} ->
            [{G, Ns} || {G, Ns} <- NodeSGroups, G /= SGroupName]
    end.

rm_s_group_nodes_from_conf(SGroupName, NodesToRm) ->
    case application:get_env(kernel, s_groups) of
        undefined ->
            [];
        {ok, []} ->
            [];
        {ok, NodeSGroups} ->
            case lists:keyfind(SGroupName, 1, NodeSGroups) of 
                false ->
                    NodeSGroups;
                {SGroupName, Nodes}->
                    NewSGroupNodes = Nodes -- NodesToRm,
                    lists:keyreplace(SGroupName, 1, NodeSGroups, {SGroupName, NewSGroupNodes})
            end
    end.


%%%====================================================================================
%%% Draft function for registered_names, {s_group, SGroupName}handle_call({registered_names, {s_group, SGroupName}}, From, S)
%%%====================================================================================
s_group_names([], Names, _SGroupName) ->
    Names;
s_group_names([{Name, SGroupName1} | Tail], Names, SGroupName) when SGroupName1 =:= SGroupName ->
    s_group_names(Tail, [{Name, SGroupName} | Names], SGroupName);
s_group_names([{_Name, _SGroupName1} | Tail], Names, SGroupName) ->
    s_group_names(Tail, Names, SGroupName).

