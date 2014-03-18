%%======================================================================
%%
%% Leo Manager
%%
%% Copyright (c) 2012-2014 Rakuten, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% ---------------------------------------------------------------------
%% LeoFS Manager - Console
%% @doc
%% @end
%%======================================================================
-module(leo_manager_console).

-author('Yosuke Hara').

-include("leo_manager.hrl").
-include_lib("leo_commons/include/leo_commons.hrl").
-include_lib("leo_logger/include/leo_logger.hrl").
-include_lib("leo_redundant_manager/include/leo_redundant_manager.hrl").
-include_lib("leo_s3_libs/include/leo_s3_auth.hrl").
-include_lib("leo_s3_libs/include/leo_s3_user.hrl").
-include_lib("leo_s3_libs/include/leo_s3_bucket.hrl").
-include_lib("eunit/include/eunit.hrl").

%% API
-export([start_link/2, start_link/3, stop/0]).
-export([init/1, handle_call/3]).


%%----------------------------------------------------------------------
%% API
%%----------------------------------------------------------------------
start_link(Formatter, Params) ->
    start_link(Formatter, Params, undefined).

start_link(Formatter, Params, PluginMod) ->
    tcp_server:start_link(?MODULE, [Formatter, PluginMod], Params).

stop() ->
    tcp_server:stop().


%%----------------------------------------------------------------------
%% Callback function(s)
%%----------------------------------------------------------------------
init([Formatter, PluginMod]) ->
    {ok, #state{formatter  = Formatter,
                plugin_mod = PluginMod
               }}.


%%----------------------------------------------------------------------
%% Operation-1
%%----------------------------------------------------------------------
%% Command: "help"
%%
handle_call(_Socket, <<?CMD_HELP, ?CRLF>>, #state{formatter  = Formatter,
                                                  plugin_mod = PluginMod} = State) ->
    Fun = fun() ->
                  Formatter:help(PluginMod)
          end,
    Reply = invoke(?CMD_HELP, Formatter, Fun),
    {reply, Reply, State};


%% Command: "version"
%%
handle_call(_Socket, <<?CMD_VERSION, ?CRLF>>, #state{formatter = Formatter} = State) ->
    {ok, Version} = version(),
    Reply = Formatter:version(Version),
    {reply, Reply, State};


%% Command: "_user-id_"
%%
handle_call(_Socket, ?USER_ID, #state{formatter = Formatter} = State) ->
    Reply = Formatter:user_id(),
    {reply, Reply, State};


%% Command: "_password_"
%%
handle_call(_Socket, ?PASSWORD, #state{formatter = Formatter} = State) ->
    Reply = Formatter:password(),
    {reply, Reply, State};


%% Command: "_authorized_"
%%
handle_call(_Socket, ?AUTHORIZED, #state{formatter = Formatter} = State) ->
    Reply = Formatter:authorized(),
    {reply, Reply, State};


%% Command: "_authorized_"
%%
handle_call(_Socket, <<?LOGIN, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Reply = case login(Command, Option) of
                {ok, User, Credential} ->
                    Formatter:login(User, Credential);
                {error, Cause} ->
                    Formatter:error(Cause)
            end,
    {reply, Reply, State};


%% Command: "status"
%% Command: "status ${NODE_NAME}"
%%
handle_call(_Socket, <<?CMD_STATUS, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case status(Command, Option) of
                      {ok, {node_list, Props}} ->
                          Formatter:system_info_and_nodes_stat(Props);
                      {ok, {?SERVER_TYPE_GATEWAY = Type, NodeStatus}} ->
                          Formatter:node_stat(Type, NodeStatus);
                      {ok, {?SERVER_TYPE_STORAGE = Type, NodeStatus}} ->
                          Formatter:node_stat(Type, NodeStatus);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_STATUS, Formatter, Fun),
    {reply, Reply, State};


%% Command : "detach ${NODE_NAME}"
%%
handle_call(_Socket, <<?CMD_DETACH, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case detach(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_DETACH, Formatter, Fun),
    {reply, Reply, State};


%% Command: "suspend ${NODE_NAME}"
%%
handle_call(_Socket, <<?CMD_SUSPEND, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case suspend(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_SUSPEND, Formatter, Fun),
    {reply, Reply, State};


%% Command: "resume ${NODE_NAME}"
%%
handle_call(_Socket, <<?CMD_RESUME, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case resume(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_RESUME, Formatter, Fun),
    {reply, Reply, State};


%% Command: "start"
%%
handle_call(Socket, <<?CMD_START, ?CRLF>> = Command,
            #state{formatter = Formatter} = State) ->
    Socket_1 = case Formatter of
                   ?MOD_TEXT_FORMATTER -> Socket;
                   _ -> null
               end,

    Fun = fun() ->
                  case start(Socket_1, Command) of
                      ok ->
                          Formatter:ok();
                      {error, {bad_nodes, BadNodes}} ->
                          Formatter:bad_nodes(BadNodes);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_START, Formatter, Fun),
    {reply, Reply, State};


%% Command: "rebalance"
%%
handle_call(Socket, <<?CMD_REBALANCE, ?CRLF>> = Command,
            #state{formatter = Formatter} = State) ->
    Socket_1 = case Formatter of
                   ?MOD_TEXT_FORMATTER -> Socket;
                   _ -> null
               end,

    Fun = fun() ->
                  case rebalance(Socket_1, Command) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_REBALANCE, Formatter, Fun),
    {reply, Reply, State};


%%----------------------------------------------------------------------
%% Operation-2
%%----------------------------------------------------------------------
%% Command: "du ${NODE_NAME}"
%%
handle_call(_Socket, <<?CMD_DU, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case du(Command, Option) of
                      {ok, {Option1, StorageStats}} ->
                          Formatter:du(Option1, StorageStats);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_DU, Formatter, Fun),
    {reply, Reply, State};


%% Command: "compact ${NODE_NAME}"
%%
handle_call(_Socket, <<?CMD_COMPACT, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case compact(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {ok, Status} ->
                          Formatter:compact_status(Status);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_COMPACT, Formatter, Fun),
    {reply, Reply, State};


%%----------------------------------------------------------------------
%% Operation-3
%%----------------------------------------------------------------------
%% Command: "create-user ${USER_ID} ${PASSWORD}"
%%
handle_call(_Socket, <<?CMD_CREATE_USER, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case create_user(Command, Option) of
                      {ok, PropList} ->
                          AccessKeyId     = leo_misc:get_value('access_key_id',     PropList),
                          SecretAccessKey = leo_misc:get_value('secret_access_key', PropList),
                          Formatter:credential(AccessKeyId, SecretAccessKey);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_CREATE_USER, Formatter, Fun),
    {reply, Reply, State};


%% Command: "update-user-role ${USER_ID} ${ROLE}"
%%
handle_call(_Socket, <<?CMD_UPDATE_USER_ROLE, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case update_user_role(Command, Option) of
                      ok ->
                          Formatter:ok();
                      not_found = Cause ->
                          Formatter:error(Cause);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_UPDATE_USER_ROLE, Formatter, Fun),
    {reply, Reply, State};


%% Command: "update-user-password ${USER_ID} ${PASSWORD}"
%%
handle_call(_Socket, <<?CMD_UPDATE_USER_PW, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case update_user_password(Command, Option) of
                      ok ->
                          Formatter:ok();
                      not_found = Cause ->
                          Formatter:error(Cause);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_UPDATE_USER_PW, Formatter, Fun),
    {reply, Reply, State};


%% Command: "delete-user ${USER_ID} ${PASSWORD}"
%%
handle_call(_Socket, <<?CMD_DELETE_USER, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case delete_user(Command, Option) of
                      ok ->
                          Formatter:ok();
                      not_found = Cause ->
                          Formatter:error(Cause);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_DELETE_USER, Formatter, Fun),
    {reply, Reply, State};


%% Command: "get-users"
%%
handle_call(_Socket, <<?CMD_GET_USERS, ?CRLF>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case get_users(Command) of
                      {ok, List} ->
                          Formatter:users(List);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_GET_USERS, Formatter, Fun),
    {reply, Reply, State};


%% Command: "end-endpoint ${END_POINT}"
%%
handle_call(_Socket, <<?CMD_ADD_ENDPOINT, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case set_endpoint(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_ADD_ENDPOINT, Formatter, Fun),
    {reply, Reply, State};

handle_call(_Socket, <<?CMD_SET_ENDPOINT, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case set_endpoint(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_SET_ENDPOINT, Formatter, Fun),
    {reply, Reply, State};


%% Command: "get-endpoints"
%%
handle_call(_Socket, <<?CMD_GET_ENDPOINTS, ?CRLF>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case get_endpoints(Command) of
                      {ok, EndPoints} ->
                          Formatter:endpoints(EndPoints);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_GET_ENDPOINTS, Formatter, Fun),
    {reply, Reply, State};


%% Command: "del-endpoint ${end_point}"
%%
handle_call(_Socket, <<?CMD_DEL_ENDPOINT, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case delete_endpoint(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_DEL_ENDPOINT, Formatter, Fun),
    {reply, Reply, State};


%% Command: "add-buckets ${bucket} ${access-key-id}"
%%
handle_call(_Socket, <<?CMD_ADD_BUCKET, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case add_bucket(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_ADD_BUCKET, Formatter, Fun),
    {reply, Reply, State};


%% Command: "delete-buckets ${bucket} ${access-key-id}"
%%
handle_call(_Socket, <<?CMD_DELETE_BUCKET, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case delete_bucket(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_DELETE_BUCKET, Formatter, Fun),
    {reply, Reply, State};


%% Command: "get-buckets"
%%
handle_call(_Socket, <<?CMD_GET_BUCKETS, ?CRLF>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case get_buckets(Command) of
                      {ok, Buckets} ->
                          Formatter:buckets(Buckets);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_GET_BUCKETS, Formatter, Fun),
    {reply, Reply, State};


%% Command: "get-bucket ${access-key-id}"
%%
handle_call(_Socket, <<?CMD_GET_BUCKET_BY_ACCESS_KEY, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case get_bucket_by_access_key(Command, Option) of
                      {ok, Buckets} ->
                          Formatter:bucket_by_access_key(Buckets);
                      not_found ->
                          Formatter:error("Bucket not found");
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_GET_BUCKETS, Formatter, Fun),
    {reply, Reply, State};


%% Command: "chown-bucket ${bucket} ${new-access-key-id}"
%%
handle_call(_Socket, <<?CMD_CHANGE_BUCKET_OWNER, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case change_bucket_owner(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_CHANGE_BUCKET_OWNER, Formatter, Fun),
    {reply, Reply, State};


%% Command: "update-acl ${bucket} ${canned_acl}"
%%
handle_call(_Socket, <<?CMD_UPDATE_ACL, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case update_acl(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_UPDATE_ACL, Formatter, Fun),
    {reply, Reply, State};


%% Command: "whereis ${PATH}"
%%
handle_call(_Socket, <<?CMD_WHEREIS, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case whereis(Command, Option) of
                      {ok, AssignedInfo} ->
                          Formatter:whereis(AssignedInfo);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_WHEREIS, Formatter, Fun),
    {reply, Reply, State};


%% Command: "recover file|node ${PATH}|${NODE}"
%%
handle_call(_Socket, <<?CMD_RECOVER, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case recover(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_RECOVER, Formatter, Fun),
    {reply, Reply, State};


%% Command: "purge ${PATH}"
%%
handle_call(_Socket, <<?CMD_PURGE, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case purge(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_PURGE, Formatter, Fun),
    {reply, Reply, State};


%% Command: "remove ${GATEWAY_NODE}"
%%
handle_call(_Socket, <<?CMD_REMOVE, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case remove(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_REMOVE, Formatter, Fun),
    {reply, Reply, State};


%% Command: "backup-mnesia ${MNESIA_BACKUPFILE}"
%%
handle_call(_Socket, <<?CMD_BACKUP_MNESIA, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case backup_mnesia(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_BACKUP_MNESIA, Formatter, Fun),
    {reply, Reply, State};


%% Command: "restore-mnesia ${MNESIA_BACKUPFILE}"
%%
handle_call(_Socket, <<?CMD_RESTORE_MNESIA, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case restore_mnesia(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_RESTORE_MNESIA, Formatter, Fun),
    {reply, Reply, State};


%% Command: "update-managers ${MANAGER_MASTER} ${MANAGER_SLAVE}"
%%
handle_call(_Socket, <<?CMD_UPDATE_MANAGERS, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case update_manager_nodes(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_UPDATE_MANAGERS, Formatter, Fun),
    {reply, Reply, State};


%% Command: "history"
%%
handle_call(_Socket, <<?CMD_HISTORY, ?CRLF>>, #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case leo_manager_mnesia:get_histories_all() of
                      {ok, Histories} ->
                          Formatter:histories(Histories);
                      not_found ->
                          Formatter:histories([]);
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_HISTORY, Formatter, Fun),
    {reply, Reply, State};


%% Command: "dump-ring ${NODE}"
%%
handle_call(_Socket, <<?CMD_DUMP_RING, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case dump_ring(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_DUMP_RING, Formatter, Fun),
    {reply, Reply, State};


%%----------------------------------------------------------------------
%% Operation-4
%%----------------------------------------------------------------------
%% Command: "join-cluster [${REMOTE_MANAGER_NODE}, ${REMOTE_MANAGER_NODE}, ...]"
%%
handle_call(_Socket, <<?CMD_JOIN_CLUSTER, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case join_cluster(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_JOIN_CLUSTER, Formatter, Fun),
    {reply, Reply, State};

%% Command: "remove-cluster [${REMOTE_MANAGER_NODE}, ${REMOTE_MANAGER_NODE}, ...]"
%%
handle_call(_Socket, <<?CMD_REMOVE_CLUSTER, ?SPACE, Option/binary>> = Command,
            #state{formatter = Formatter} = State) ->
    Fun = fun() ->
                  case remove_cluster(Command, Option) of
                      ok ->
                          Formatter:ok();
                      {error, Cause} ->
                          Formatter:error(Cause)
                  end
          end,
    Reply = invoke(?CMD_REMOVE_CLUSTER, Formatter, Fun),
    {reply, Reply, State};


%% Command: "quit"
%%
handle_call(_Socket, <<?CMD_QUIT, ?CRLF>>, State) ->
    {close, <<?BYE>>, State};


handle_call(_Socket, <<?CRLF>>, State) ->
    {reply, "", State};


handle_call(_Socket, _Data, #state{formatter = Formatter,
                                   plugin_mod = undefined} = State) ->
    Reply = Formatter:error(?ERROR_NOT_SPECIFIED_COMMAND),
    {reply, Reply, State};

handle_call(Socket, Data, #state{plugin_mod = PluginMod} = State) ->
    PluginMod:handle_call(Socket, Data, State).


%%----------------------------------------------------------------------
%% Inner function(s)
%%----------------------------------------------------------------------
%% Invoke a command
%% @private
-spec(invoke(string(), atom(), function()) ->
             string()).
invoke(Command, Formatter, Fun) ->
    case leo_manager_mnesia:get_available_command_by_name(Command) of
        not_found ->
            Formatter:error(?ERROR_NOT_SPECIFIED_COMMAND);
        _ ->
            Fun()
    end.


%% @doc Backup files of manager's mnesia
%% @private
-spec(backup_mnesia(binary(), binary()) ->
             ok | {error, any()}).
backup_mnesia(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),
    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_NOT_SPECIFIED_NODE};
        [BackupFile|_] ->
            leo_manager_mnesia:backup(BackupFile)
    end.


%% @doc Restore mnesia from backup files
%% @private
-spec(restore_mnesia(binary(), binary()) ->
             ok | {error, any()}).
restore_mnesia(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),
    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_NOT_SPECIFIED_NODE};
        [BackupFile|_] ->
            leo_manager_mnesia:restore(BackupFile)
    end.


%% @doc Update manager's node to alternate node
%% @private
-spec(update_manager_nodes(binary(), binary()) ->
             ok | {error, any()}).
update_manager_nodes(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),
    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [Master, Slave|_] ->
            leo_manager_api:update_manager_nodes(
              [list_to_atom(Master), list_to_atom(Slave)]);
        _ ->
            {error, ?ERROR_NOT_SPECIFIED_NODE}
    end.


%% @doc Output ring of a targe node
%% @private
dump_ring(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),
    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [Node|_] ->
            rpc:call(list_to_atom(Node), leo_redundant_manager_api, dump, [both]);
        _ ->
            {error, ?ERROR_NOT_SPECIFIED_NODE}
    end.


%% @doc Join a cluster
%% @private
join_cluster(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),
    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_NOT_SPECIFIED_NODE};
        Nodes ->
            case join_cluster_1(Nodes) of
                {ok, ClusterId} ->
                    leo_manager_api:update_cluster_member(Nodes, ClusterId);
                Other ->
                    Other
            end
    end.

join_cluster_1([]) ->
    {error, ?ERROR_COULD_NOT_CONNECT};
join_cluster_1([Node|Rest]) ->
    {ok, SystemConf} = leo_cluster_tbl_conf:get(),
    RPCNode = leo_rpc:node(),
    Managers = case ?env_partner_of_manager_node() of
                   [] -> [RPCNode];
                   [Partner|_] ->
                       case rpc:call(Partner, leo_rpc, node, []) of
                           {_,_Cause} ->
                               [RPCNode];
                           Partner_1 ->
                               [RPCNode, Partner_1]
                       end
               end,

    case catch leo_rpc:call(list_to_atom(Node), leo_manager_api,
                            join_cluster, [Managers, SystemConf]) of
        {ok, #?SYSTEM_CONF{cluster_id = ClusterId} = RemoteSystemConf} ->
            case leo_mdcr_tbl_cluster_info:get(ClusterId) of
                not_found ->
                    #?SYSTEM_CONF{dc_id = DCId,
                                  n = N, r = R, w = W, d = D,
                                  bit_of_ring = BitOfRing,
                                  num_of_dc_replicas = NumOfReplicas,
                                  num_of_rack_replicas = NumOfRaclReplicas
                                 } = RemoteSystemConf,
                    case leo_mdcr_tbl_cluster_info:update(
                           #cluster_info{cluster_id = ClusterId,
                                         dc_id = DCId,
                                         n = N, r = R, w = W, d = D,
                                         bit_of_ring = BitOfRing,
                                         num_of_dc_replicas = NumOfReplicas,
                                         num_of_rack_replicas = NumOfRaclReplicas}) of
                        ok ->
                            {ok, ClusterId};
                        _Other ->
                            {error, ?ERROR_FAIL_ACCESS_MNESIA}
                    end;
                {ok, _} ->
                    {error, ?ERROR_ALREADY_HAS_SAME_CLUSTER};
                _Other ->
                    {error, ?ERROR_FAIL_ACCESS_MNESIA}
            end;
        _Error ->
            join_cluster_1(Rest)
    end.


%% @doc Remove a cluster
%% @private
remove_cluster(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),
    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_NOT_SPECIFIED_NODE};
        Nodes ->
            remove_cluster_1(Nodes)
    end.

remove_cluster_1([]) ->
    {error, ?ERROR_COULD_NOT_CONNECT};
remove_cluster_1([Node|Rest]) ->
    {ok, SystemConf} = leo_cluster_tbl_conf:get(),
    case catch leo_rpc:call(list_to_atom(Node), leo_manager_api, remove_cluster, [SystemConf]) of
        {ok, #?SYSTEM_CONF{cluster_id = ClusterId}} ->
            leo_mdcr_tbl_cluster_info:delete(ClusterId);
        _Error ->
            remove_cluster_1(Rest)
    end.


%% @doc Retrieve version of the system
%% @private
-spec(version() ->
             {ok, string() | list()}).
version() ->
    case application:get_env(leo_manager, system_version) of
        {ok, Version} ->
            {ok, Version};
        _ ->
            {ok, []}
    end.


%% @doc Exec login
%% @private
-spec(login(binary(), binary()) ->
             {ok, #user{}, list()} | {error, any()}).
login(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),
    Token = string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER),

    case (erlang:length(Token) == 2) of
        true ->
            [UserId, Password] = Token,
            case leo_s3_user:auth(UserId, Password) of
                {ok, #user{id = UserId} = User} ->
                    case leo_s3_user:get_credential_by_id(UserId) of
                        {ok, Credential} ->
                            {ok, User, Credential};
                        Error ->
                            Error
                    end;
                Error ->
                    Error
            end;
        false ->
            {error, invalid_args}
    end.


%% @doc Retrieve state of each node
%% @private
-spec(status(binary(), binary()) ->
             {ok, any()} | {error, any()}).
status(_CmdBody, Option) ->
    Token = string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER),

    case (erlang:length(Token) == 0) of
        true ->
            %% Reload and store system-conf
            case ?env_mode_of_manager() of
                'master' ->
                    case leo_cluster_tbl_conf:get() of
                        {ok, SystemConf} ->
                            case leo_manager_api:load_system_config() of
                                SystemConf -> void;
                                _ ->
                                    leo_manager_api:load_system_config_with_store_data()
                            end;
                        _ ->
                            void
                    end;
                _ ->
                    void
            end,

            %% Retrieve the status
            status(node_list);
        false ->
            [Node|_] = Token,
            status({node_state, Node})
    end.

status(node_list) ->
    case leo_cluster_tbl_conf:get() of
        {ok, SystemConf} ->
            Version = case application:get_env(leo_manager, system_version) of
                          {ok, Vsn} -> Vsn;
                          undefined -> []
                      end,
            {ok, {RingHash0, RingHash1}} = leo_redundant_manager_api:checksum(ring),

            S1 = case leo_manager_mnesia:get_storage_nodes_all() of
                     {ok, R1} ->
                         lists:map(fun(N) ->
                                           {?SERVER_TYPE_STORAGE,
                                            atom_to_list(N#node_state.node),
                                            atom_to_list(N#node_state.state),
                                            N#node_state.ring_hash_new,
                                            N#node_state.ring_hash_old,
                                            N#node_state.when_is}
                                   end, R1);
                     _ ->
                         []
                 end,
            S2 = case leo_manager_mnesia:get_gateway_nodes_all() of
                     {ok, R2} ->
                         lists:map(fun(N) ->
                                           {?SERVER_TYPE_GATEWAY,
                                            atom_to_list(N#node_state.node),
                                            atom_to_list(N#node_state.state),
                                            N#node_state.ring_hash_new,
                                            N#node_state.ring_hash_old,
                                            N#node_state.when_is}
                                   end, R2);
                     _ ->
                         []
                 end,
            {ok, {node_list, [{system_config, SystemConf},
                              {version,       Version},
                              {ring_hash,     [RingHash0, RingHash1]},
                              {nodes,         S1 ++ S2}
                             ]}};
        {error, Cause} ->
            {error, Cause}
    end;

status({node_state, Node}) ->
    case leo_manager_api:get_node_status(Node) of
        {ok, {Type, State}} ->
            {ok, {Type, State}};
        {error, Cause} ->
            {error, Cause}
    end.


%% @doc Launch the storage cluster
%% @private
-spec(start(port()|null, binary()) ->
             ok | {error, any()}).
start(Socket, CmdBody) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case leo_manager_mnesia:get_storage_nodes_all() of
        {ok, _} ->
            case leo_manager_api:get_system_status() of
                ?STATE_STOP ->
                    {ok, SystemConf} = leo_cluster_tbl_conf:get(),

                    case leo_manager_mnesia:get_storage_nodes_by_status(?STATE_ATTACHED) of
                        {ok, Nodes} when length(Nodes) >= SystemConf#?SYSTEM_CONF.n ->
                            case leo_manager_api:start(Socket) of
                                ok ->
                                    ok;
                                {error, timeout = Cause} ->
                                    {error, Cause};
                                {error, BadNodes} ->
                                    {error, {bad_nodes, [N || {N,_} <- BadNodes]}}
                                    %% lists:foldl(fun(Node, Acc) ->
                                    %%                     Acc ++ [Node]
                                    %%             end, [], BadNodes)}}
                            end;
                        {ok, Nodes} when length(Nodes) < SystemConf#?SYSTEM_CONF.n ->
                            {error, "Attached nodes less than # of replicas"};
                        not_found ->
                            %% status of all-nodes is 'suspend' or 'restarted'
                            {error, ?ERROR_ALREADY_STARTED};
                        Error ->
                            Error
                    end;
                ?STATE_RUNNING ->
                    {error, ?ERROR_ALREADY_STARTED}
            end;
        _ ->
            {error, ?ERROR_NOT_STARTED}
    end.


%% @doc Detach a storage-node
%% @private
-spec(detach(binary(), binary()) ->
             ok | {error, {atom(), string()}} | {error, any()}).
detach(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),
    {ok, SystemConf} = leo_cluster_tbl_conf:get(),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_NOT_SPECIFIED_NODE};
        [Node|_] ->
            NodeAtom = list_to_atom(Node),

            case leo_manager_mnesia:get_storage_node_by_name(NodeAtom) of
                %% target-node is 'attached', then removed it from 'member-table'
                {ok, [#node_state{state = ?STATE_ATTACHED} = NodeState|_]} ->
                    ok = leo_manager_mnesia:delete_storage_node(NodeState),
                    ok = leo_manager_cluster_monitor:demonitor(NodeAtom),
                    ok = leo_redundant_manager_api:delete_member_by_node(NodeAtom),
                    ok;
                _ ->
                    %% allow to detach the node?
                    %% if it's ok then execute to detach it
                    N = SystemConf#?SYSTEM_CONF.n,
                    case allow_to_detach_node_1(N) of
                        ok ->
                            case allow_to_detach_node_2(N, NodeAtom) of
                                ok ->
                                    case leo_manager_api:detach(NodeAtom) of
                                        ok ->
                                            ok;
                                        {error, Cause} ->
                                            {error, Node, Cause}
                                    end;
                                Error ->
                                    Error
                            end;
                        Error ->
                            Error
                    end
            end
    end.


%% @private
-spec(allow_to_detach_node_1(pos_integer()) ->
             ok | {error, any()}).
allow_to_detach_node_1(N) ->
    case leo_manager_mnesia:get_storage_nodes_by_status(?STATE_DETACHED) of
        {ok, Nodes} when length(Nodes) < N ->
            ok;
        {ok,_Nodes} ->
            {error, "Detached nodes greater than or equal # of replicas"};
        not_found ->
            ok;
        Error ->
            Error
    end.

-spec(allow_to_detach_node_2(pos_integer(), atom()) ->
             ok | {error, any()}).
allow_to_detach_node_2(N, NodeAtom) ->
    IsRunning = case leo_manager_mnesia:get_storage_node_by_name(NodeAtom) of
                    {ok, [#node_state{state = ?STATE_RUNNING}|_]} ->
                        true;
                    {ok, [#node_state{state = _}|_]} ->
                        false;
                    _ ->
                        {error, "Could not get node-status"}
                end,

    case IsRunning of
        {error, Cause} ->
            {error, Cause};
        _ ->
            case leo_manager_mnesia:get_storage_nodes_by_status(?STATE_RUNNING) of
                {ok, Nodes} when IsRunning == false andalso length(Nodes) >= N ->
                    ok;
                {ok, Nodes} when IsRunning == true  andalso length(Nodes) > N ->
                    ok;
                {ok,_Nodes} ->
                    {error, "Running nodes less than # of replicas"};
                not_found ->
                    {error, "Could not get node-status"};
                _Error ->
                    {error, "Could not get node-status"}
            end
    end.


%% @doc Suspend a storage-node
%% @private
-spec(suspend(binary(), binary()) ->
             ok | {error, any()}).
suspend(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_NOT_SPECIFIED_NODE};
        [Node|_] ->
            NodeAtom = list_to_atom(Node),
            case leo_manager_mnesia:get_storage_node_by_name(NodeAtom) of
                {ok, [#node_state{state = ?STATE_RUNNING}|_]} ->
                    case leo_manager_api:suspend(NodeAtom) of
                        ok ->
                            ok;
                        {error, Cause} ->
                            {error, Cause}
                    end;
                _ ->
                    {error, ?ERROR_COULD_NOT_SUSPEND_NODE}
            end
    end.


%% @doc Resume a storage-node
%% @private
-spec(resume(binary(), binary()) ->
             ok | {error, any()}).
resume(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_NOT_SPECIFIED_NODE};
        [Node|_] ->
            NodeAtom = list_to_atom(Node),
            case leo_manager_mnesia:get_storage_node_by_name(NodeAtom) of
                {ok, [#node_state{state = ?STATE_RUNNING}|_]} ->
                    {error, ?ERROR_COULD_NOT_RESUME_NODE};
                {ok, [#node_state{state = ?STATE_ATTACHED}|_]} ->
                    {error, ?ERROR_COULD_NOT_RESUME_NODE};
                {ok, [#node_state{state = ?STATE_DETACHED}|_]} ->
                    {error, ?ERROR_COULD_NOT_RESUME_NODE};
                {ok, [#node_state{state = ?STATE_STOP}|_]} ->
                    {error, ?ERROR_COULD_NOT_RESUME_NODE};
                _ ->
                    case leo_manager_api:resume(NodeAtom) of
                        ok ->
                            ok;
                        {error, Cause} ->
                            {error, Cause}
                    end
            end
    end.


%% @doc Rebalance the storage cluster
%% @private
-spec(rebalance(port()|null, binary()) ->
             ok | {error, any()}).
rebalance(Socket, CmdBody) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case leo_manager_api:rebalance(Socket) of
        ok ->
            ok;
        {error, Cause} ->
            {error, Cause}
    end.


%% @doc Purge an object from the cache
%% @private
-spec(purge(binary(), binary()) ->
             ok | {error, any()}).
purge(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_INVALID_PATH};
        [Key|_] ->
            case leo_manager_api:purge(Key) of
                ok ->
                    ok;
                {error, Cause} ->
                    {error, Cause}
            end
    end.


%% @doc remove a gateway-node
%% @private
-spec(remove(binary(), binary()) ->
             ok | {error, any()}).
remove(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_INVALID_PATH};
        [Node|_] ->
            case leo_manager_api:remove(Node) of
                ok ->
                    ok;
                {error, Cause} ->
                    {error, Cause}
            end
    end.


%% @doc Retrieve the storage stats
%% @private
-spec(du(binary(), binary()) ->
             ok | {error, any()}).
du(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_NOT_SPECIFIED_NODE};
        Tokens ->
            Mode = case length(Tokens) of
                       1 ->
                           {summary, lists:nth(1, Tokens)};
                       2 ->
                           case lists:nth(1, Tokens) of
                               "detail" ->
                                   {detail, lists:nth(2, Tokens)};
                               _ ->
                                   {error, ?ERROR_INVALID_ARGS}
                           end;
                       _ -> {error, ?ERROR_INVALID_ARGS}
                   end,

            case Mode of
                {error, _Cause} ->
                    {error, ?ERROR_INVALID_ARGS};
                {Option1, Node1} ->
                    case leo_manager_api:stats(Option1, Node1) of
                        {ok, StatsList} ->
                            {ok, {Option1, StatsList}};
                        {error, Cause} ->
                            {error, Cause}
                    end
            end
    end.


%% @doc Compact target node of objects into the object-storages
%% @private
-spec(compact(binary(), binary()) ->
             ok | {error, any()}).
compact(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_NO_CMODE_SPECIFIED};
        [Mode, Node|Rest] ->
            %% command patterns:
            %%   compact start ${storage-node} all | ${num_of_targets} [${num_of_compact_procs}]
            %%   compact suspend ${storage-node}
            %%   compact resume ${storage-node}
            %%   compact status ${storage-node}
            case catch compact(Mode, list_to_atom(Node), Rest) of
                ok ->
                    ok;
                {ok, Status} ->
                    {ok, Status};
                {_, Cause} ->
                    {error, Cause}
            end;
        [_Mode|_Rest] ->
            {error, ?ERROR_NOT_SPECIFIED_NODE}
    end.


-spec(compact(string(), atom(), list()) ->
             ok | {error, any()}).
compact(?COMPACT_START = Mode, Node, [?COMPACT_TARGET_ALL | Rest]) ->
    compact(Mode, Node, 'all', Rest);

compact(?COMPACT_START = Mode, Node, [NumOfTargets0 | Rest]) ->
    case catch list_to_integer(NumOfTargets0) of
        {'EXIT', _} ->
            {error, ?ERROR_INVALID_ARGS};
        NumOfTargets1 ->
            compact(Mode, Node, NumOfTargets1, Rest)
    end;

compact(Mode, Node, _) ->
    leo_manager_api:compact(Mode, Node).


-spec(compact(string(), atom(), list(), list()) ->
             ok | {error, any()}).
compact(?COMPACT_START = Mode, Node, NumOfTargets, []) ->
    leo_manager_api:compact(Mode, Node, NumOfTargets, ?env_num_of_compact_proc());

compact(?COMPACT_START = Mode, Node, NumOfTargets, [MaxProc1|_]) ->
    case catch list_to_integer(MaxProc1) of
        {'EXIT', _} ->
            {error, ?ERROR_INVALID_ARGS};
        MaxProc2 ->
            leo_manager_api:compact(Mode, Node, NumOfTargets, MaxProc2)
    end;

compact(_,_,_, _) ->
    {error, ?ERROR_INVALID_ARGS}.


%% @doc Retrieve information of an Assigned object
%% @private
-spec(whereis(binary(), binary()) ->
             ok | {error, any()}).
whereis(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),
    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_INVALID_PATH};
        Key ->
            HasRoutingTable = (leo_redundant_manager_api:checksum(ring) >= 0),

            case catch leo_manager_api:whereis(Key, HasRoutingTable) of
                {ok, AssignedInfo} ->
                    {ok, AssignedInfo};
                {_, Cause} ->
                    {error, Cause}
            end
    end.


%% @doc Recover object(s) by a key/node
%% @private
-spec(recover(binary(), binary()) ->
             ok | {error, any()}).
recover(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_INVALID_PATH};
        [Op, Key |Rest] when Rest == [] ->
            HasRoutingTable = (leo_redundant_manager_api:checksum(ring) >= 0),

            case catch leo_manager_api:recover(Op, Key, HasRoutingTable) of
                ok ->
                    ok;
                {_, Cause} ->
                    {error, Cause}
            end;
        _ ->
            {error, ?ERROR_INVALID_ARGS}
    end.


%% @doc Create a user account (S3)
%% @private
-spec(create_user(binary(), binary()) ->
             ok | {error, any()}).
create_user(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    Ret = case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
              [UserId] ->
                  {ok, {UserId, []}};
              [UserId, Password] ->
                  {ok, {UserId, Password}};
              _ ->
                  {error, ?ERROR_INVALID_ARGS}
          end,

    case Ret of
        {ok, {Arg0, Arg1}} ->
            case leo_s3_user:add(Arg0, Arg1, true) of
                {ok, Keys} ->
                    AccessKeyId     = leo_misc:get_value(access_key_id,     Keys),
                    SecretAccessKey = leo_misc:get_value(secret_access_key, Keys),

                    case Arg1 of
                        [] ->
                            ok = leo_s3_user:update(#user{id       = Arg0,
                                                          role_id  = ?ROLE_GENERAL,
                                                          password = SecretAccessKey});
                        _ ->
                            void
                    end,
                    {ok, [{access_key_id,     AccessKeyId},
                          {secret_access_key, SecretAccessKey}]};
                {error,_Cause} ->
                    {error, ?ERROR_COULD_NOT_ADD_USER}
            end;
        {error, Cause} ->
            {error, Cause}
    end.


%% @doc Update user's role-id
%% @private
-spec(update_user_role(binary(), binary()) ->
             ok | {error, any()}).
update_user_role(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [UserId, RoleId|_] ->
            case leo_s3_user:update(#user{id       = UserId,
                                          role_id  = list_to_integer(RoleId),
                                          password = <<>>}) of
                ok ->
                    ok;
                not_found ->
                    {error, ?ERROR_USER_NOT_FOUND};
                {error,_Cause} ->
                    {error, ?ERROR_COULD_NOT_UPDATE_USER}
            end;
        _ ->
            {error, ?ERROR_INVALID_ARGS}
    end.


%% @doc Update user's password
%% @private
-spec(update_user_password(binary(), binary()) ->
             ok | {error, any()}).
update_user_password(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [UserId, Password|_] ->
            case leo_s3_user:find_by_id(UserId) of
                {ok, #user{role_id = RoleId}} ->
                    case leo_s3_user:update(#user{id       = UserId,
                                                  role_id  = RoleId,
                                                  password = Password}) of
                        ok ->
                            ok;
                        {error, Cause} ->
                            {error, Cause}
                    end;
                not_found ->
                    {error, ?ERROR_USER_NOT_FOUND};
                {error,_Cause} ->
                    {error, ?ERROR_COULD_NOT_GET_USER}
            end;
        _ ->
            {error, ?ERROR_INVALID_ARGS}
    end.


%% @doc Remove a user
%% @private
-spec(delete_user(binary(), binary()) ->
             ok | {error, any()}).
delete_user(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [UserId|_] ->
            case leo_s3_user:delete(UserId) of
                ok ->
                    ok;
                not_found ->
                    {error, ?ERROR_USER_NOT_FOUND};
                {error,_Cause} ->
                    {error, ?ERROR_COULD_NOT_REMOVE_USER}
            end;
        _ ->
            {error, ?ERROR_INVALID_ARGS}
    end.


%% @doc Retrieve Users
%% @private
-spec(get_users(binary()) ->
             {ok, list(#credential{})} | {error, any()}).
get_users(CmdBody) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case leo_s3_user:find_all() of
        {ok, Users} ->
            {ok, Users};
        not_found = Cause ->
            {error, Cause};
        Error ->
            Error
    end.


%% @doc Insert an Endpoint into the manager
%% @private
-spec(set_endpoint(binary(), binary()) ->
             ok | {error, any()}).
set_endpoint(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_INVALID_ARGS};
        [EndPoint|_] ->
            EndPointBin = list_to_binary(EndPoint),
            case leo_manager_api:set_endpoint(EndPointBin) of
                ok ->
                    ok;
                {error, Cause} ->
                    {error, Cause}
            end
    end.


%% @doc Retrieve an Endpoint from the manager
%% @private
-spec(get_endpoints(binary()) ->
             ok | {error, any()}).
get_endpoints(CmdBody) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case leo_s3_endpoint:get_endpoints() of
        {ok, EndPoints} ->
            {ok, EndPoints};
        not_found ->
            {error, ?ERROR_ENDPOINT_NOT_FOUND};
        {error,_Cause} ->
            {error, ?ERROR_COULD_NOT_GET_ENDPOINT}
    end.


%% @doc Remove an Endpoint from the manager
%% @private
-spec(delete_endpoint(binary(), binary()) ->
             ok | {error, any()}).
delete_endpoint(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [] ->
            {error, ?ERROR_INVALID_ARGS};
        [EndPoint|_] ->
            EndPointBin = list_to_binary(EndPoint),
            case leo_manager_api:delete_endpoint(EndPointBin) of
                ok ->
                    ok;
                {error, Cause} ->
                    {error, Cause}
            end
    end.


%% @doc Insert a Buckets in the manager
%% @private
-spec(add_bucket(binary(), binary()) ->
             ok | {error, any()}).
add_bucket(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [Bucket, AccessKey] ->
            leo_manager_api:add_bucket(AccessKey, Bucket);
        _ ->
            {error, ?ERROR_INVALID_ARGS}
    end.


%% @doc Remove a Buckets from the manager
%% @private
-spec(delete_bucket(binary(), binary()) ->
             ok | {error, any()}).
delete_bucket(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [Bucket, AccessKey] ->
            leo_manager_api:delete_bucket(AccessKey, Bucket);
        _ ->
            {error, ?ERROR_INVALID_ARGS}
    end.


%% @doc Retrieve a Buckets from the manager
%% @private
-spec(get_buckets(binary()) ->
             ok | {error, any()}).
get_buckets(CmdBody) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case catch leo_s3_bucket:find_all_including_owner() of
        {ok, Buckets} ->
            {ok, Buckets};
        not_found ->
            {error, ?ERROR_BUCKET_NOT_FOUND};
        {_,_Cause} ->
            {error, ?ERROR_COULD_NOT_GET_BUCKET}
    end.


%% @doc Retrieve a Buckets from the manager
%% @private
-spec(get_bucket_by_access_key(binary(), binary()) ->
             ok | {error, any()}).
get_bucket_by_access_key(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [AccessKey] ->
            leo_s3_bucket:find_buckets_by_id(list_to_binary(AccessKey));
        _ ->
            {error, ?ERROR_INVALID_ARGS}
    end.


%% @doc Change owner of a bucket
%% @private
-spec(change_bucket_owner(binary(), binary()) ->
             ok | {error, any()}).
change_bucket_owner(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [Bucket, NewAccessKeyId] ->
            case leo_s3_bucket:change_bucket_owner(list_to_binary(NewAccessKeyId),
                                                   list_to_binary(Bucket)) of
                ok ->
                    ok;
                not_found ->
                    {error, ?ERROR_BUCKET_NOT_FOUND};
                {error,_Cause} ->
                    {error, ?ERROR_COULD_NOT_UPDATE_BUCKET}
            end;
        _ ->
            {error, ?ERROR_INVALID_ARGS}
    end.


%% @doc Update ACLs of the specified bucket with the Canned ACL in the manager
%% @private
-spec(update_acl(binary(), binary()) ->
             ok | {error, any()}).
update_acl(CmdBody, Option) ->
    _ = leo_manager_mnesia:insert_history(CmdBody),

    case string:tokens(binary_to_list(Option), ?COMMAND_DELIMITER) of
        [Bucket, AccessKey, Permission] ->
            case leo_manager_api:update_acl(Permission,
                                            list_to_binary(AccessKey),
                                            list_to_binary(Bucket)) of
                ok ->
                    ok;
                _Error ->
                    {error, ?ERROR_COULD_NOT_UPDATE_BUCKET}
            end;
        _ ->
            {error, ?ERROR_INVALID_ARGS}
    end.
