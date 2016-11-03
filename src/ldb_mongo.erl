%%
%% Copyright (c) 2016 SyncFree Consortium.  All Rights Reserved.
%% Copyright (c) 2016 Christopher Meiklejohn.  All Rights Reserved.
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
%% -------------------------------------------------------------------

-module(ldb_mongo).
-author("Vitor Enes Duarte <vitorenesduarte@gmail.com").

-include("ldb.hrl").

-define(MONGO, mc_worker_api).
-define(DATABASE, <<"ldb">>).
-define(COLLECTION, <<"logs">>).

%% ldb_mongo callbacks
-export([log_number/0,
         push_logs/0]).

-spec log_number() -> non_neg_integer().
log_number() ->
    case get_connection() of
        {ok, Connection} ->
            EvaluationTimestamp = ldb_config:evaluation_timestamp(),
            ?MONGO:count(Connection,
                         ?COLLECTION,
                         {<<"timestamp">>, ldb_util:atom_to_binary(EvaluationTimestamp)});
        _ ->
            0
    end.

-spec push_logs() -> ok | error.
push_logs() ->
    case get_connection() of
        {ok, Connection} ->
            EvaluationTimestamp = ldb_config:evaluation_timestamp(),
            ?MONGO:insert(Connection,
                          ?COLLECTION,
                          [{<<"timestamp">>, ldb_util:atom_to_binary(EvaluationTimestamp)},
                           {<<"logs">>, get_logs()}]),
            ok;
        _ ->
            error
    end.

%% @private
get_connection() ->
    case ldb_dcos:get_app_tasks("ldb-mongo") of
        {ok, Response} ->
            {value, {_, [Task]}} = lists:keysearch(<<"tasks">>, 1, Response),
            {value, {_, Host0}} = lists:keysearch(<<"host">>, 1, Task),
            Host = binary_to_list(Host0),
            {value, {_, [Port]}} = lists:keysearch(<<"ports">>, 1, Task),

            {ok, Connection} = ?MONGO:connect([{database, ?DATABASE},
                                               {host, Host},
                                               {port, Port}]),
            {ok, Connection};
        error ->
            ldb_log:info("Cannot contact Marathon!"),
            error
    end.

%% @private
get_logs() ->
    Filename = ldb_instrumentation:log_file(),
    Lines = ldb_util:read_lines(Filename),
    Logs = lists:foldl(
        fun(Line, Acc) ->
            Acc ++ Line
        end,
        "",
        Lines
    ),
    BinaryLogs = list_to_binary(Logs),
    BinaryLogs.