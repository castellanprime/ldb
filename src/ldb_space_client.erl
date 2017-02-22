%%
%% Copyright (c) 2016 SyncFree Consortium.  All Rights Reserved.
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

-module(ldb_space_client).
-author("Vitor Enes Duarte <vitorenesduarte@gmail.com").

-include("ldb.hrl").

-behaviour(gen_server).

-define(UNKNOWN, -2).
-define(INVALID, -1).
-define(OK, 0).
-define(KEY_NOT_FOUND, 1).

%% ldb_space_client callbacks
-export([start_link/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {socket :: gen_tcp:socket()}).

-spec start_link(gen_tcp:socket()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Socket) ->
    gen_server:start_link(?MODULE, [Socket], []).

init([Socket]) ->
    ?LOG("ldb_space_client initialized! Node ~p listening to new client ~p", [node(), Socket]),
    {ok, #state{socket=Socket}}.

handle_call(Msg, _From, State) ->
    lager:warning("Unhandled call message: ~p", [Msg]),
    {noreply, State}.

handle_cast(Msg, State) ->
    lager:warning("Unhandled cast message: ~p", [Msg]),
    {noreply, State}.

handle_info({tcp, _, Data}, #state{socket=Socket}=State) ->
    handle_message(decode(Data), Socket),
    {noreply, State};

handle_info({tcp_closed, _Socket}, State) ->
    {stop, normal, State};

handle_info(Msg, State) ->
    lager:warning("Unhandled info message: ~p", [Msg]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% @private
encode(Message) ->
    JSONBinary = jsx:encode(Message),
    iolist_to_binary([JSONBinary, <<"\n">>]).

%% @private
decode(Message) ->
    Binary = list_to_binary(Message),
    jsx:decode(Binary).

%% @private
send(Reply, Socket) ->
    case gen_tcp:send(Socket, encode(Reply)) of
        ok ->
            ok;
        Error ->
            ?LOG("Failed to send message: ~p", [Error])
    end.

%% @private
handle_message(Message, Socket) ->
    %%lager:info("Message received ~p", [Message]),

    {value, {_, Key0}} = lists:keysearch(<<"key">>, 1, Message),
    {value, {_, Method0}} = lists:keysearch(<<"method">>, 1, Message),
    {value, {_, Type0}} = lists:keysearch(<<"type">>, 1, Message),

    %% @todo check if the request really has these defined
    Key = binary_to_list(Key0),
    Method = ldb_util:binary_to_atom(Method0),
    Type = ldb_util:binary_to_atom(Type0),

    LDBResult = case Method of
        create ->
            erlang:apply(ldb, create, [Key, Type]);
        query ->
            erlang:apply(ldb, query, [Key]);
        update ->
            %% @todo check if the request really has operation defined
            {value, {_, Operation0}} = lists:keysearch(<<"operation">>, 1, Message),
            Operation = parse_operation(Type, Operation0),
            case erlang:apply(ldb, update, [Key, Operation]) of
                {ok, _} ->
                    ok;
                Else ->
                    Else
            end
    end,

    Reply = create_reply(Type, LDBResult),
    %%lager:info("Reply ~p", [Reply]),

    send(Reply, Socket).

%% @private
create_reply(_Type, ok) ->
    [{code, ?OK}];
create_reply(Type, {ok, QueryResult0}) ->
    QueryResult = prepare_query_result(Type, QueryResult0),
    [{code, ?OK}, {value, QueryResult}];
create_reply(_Type, {error, not_found}) ->
    [{code, ?KEY_NOT_FOUND}];
create_reply(_Type, Error) ->
    ?LOG("Update request from client produced the following error ~p", [Error]),
    [{code, ?UNKNOWN}].

%% @private
parse_operation(Type, Operation0) ->
    {value, {_, OperationName0}} = lists:keysearch(<<"name">>, 1, Operation0),
    OperationName = ldb_util:binary_to_atom(OperationName0),

    case Type of
        gset ->
            {value, {_, Element0}} = lists:keysearch(<<"elem">>, 1, Operation0),
            {OperationName, Element0};
        gcounter ->
            OperationName;
        mvmap ->
            {value, {_, Key0}} = lists:keysearch(<<"key">>, 1, Operation0),
            {value, {_, Value0}} = lists:keysearch(<<"value">>, 1, Operation0),
            {OperationName, Key0, Value0}
    end.

%% @private
prepare_query_result(Type, QueryResult) ->
    case Type of
        gset ->
            sets:to_list(QueryResult);
        gcounter ->
            QueryResult;
        mvmap ->
            lists:map(
                fun({Key, Value}) ->
                    [{key, Key}, {values, sets:to_list(Value)}]
                end,
                QueryResult
           )
    end.
