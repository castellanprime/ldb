%%
%% Copyright (c) 2016-2018 Vitor Enes.  All Rights Reserved.
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

-module(ldb_listener).
-author("Vitor Enes Duarte <vitorenesduarte@gmail.com").

-include("ldb.hrl").

-behaviour(gen_server).

%% ldb_listener callbacks
-export([start_link/0,
         update_ignore_keys/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {backend_state :: backend_state(),
                ignore_keys :: sets:set(string())}).

-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec update_ignore_keys(sets:set(string())) -> ok.
update_ignore_keys(IgnoreKeys) ->
    gen_server:call(?MODULE, {update_ignore_keys, IgnoreKeys}, infinity).

%% gen_server callbacks
init([]) ->
    lager:info("ldb_listener initialized!"),
    {ok, #state{backend_state=ldb_backend:backend_state(),
                ignore_keys=sets:new()}}.

handle_call({update_ignore_keys, IgnoreKeys}, _Fromm, State) ->
    ldb_util:qs("LISTENER update_ignore_keys"),
    {reply, ok, State#state{ignore_keys=IgnoreKeys}};

handle_call(Msg, _From, State) ->
    lager:warning("Unhandled call message: ~p", [Msg]),
    {noreply, State}.

handle_cast(Message, #state{backend_state=BackendState,
                            ignore_keys=IgnoreKeys}=State) ->
    ldb_util:qs("LISTENER message cast"),
    MessageHandler = ldb_backend:message_handler(Message, BackendState),
    {MicroSeconds, _Result} = timer:tc(
        MessageHandler,
        [Message]
    ),

    %% record latency applying this message but
    %% ignore some keys and delta acks
    ShouldIgnore = sets:is_element(element(1, Message), IgnoreKeys)
            orelse element(2, Message) == delta_ack,
    ?DEBUG("listener: Key ~p IgnoreKeys ~p Metrics ~p", [element(1, Message), sets:to_list(IgnoreKeys), not ShouldIgnore]),
    case ShouldIgnore of
        true -> ok;
        false -> ldb_metrics:record_latency(remote, MicroSeconds)
    end,

    {noreply, State}.

handle_info(Msg, State) ->
    lager:warning("Unhandled info message: ~p", [Msg]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
