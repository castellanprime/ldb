%%
%% Copyright (c) 2018 Vitor Enes.  All Rights Reserved.
%%
%% Version 2.0 (the "License"); you may not use this file
%% This file is provided to you under the Apache License,
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

-module(ldb_vanilla_scuttlebutt_backend).
-author("Vitor Enes <vitorenesduarte@gmail.com").

-include("ldb.hrl").

-behaviour(ldb_backend).

%% ldb_backend callbacks
-export([backend_state/0,
         bottom_entry/2,
         crdt/1,
         update/3,
         memory/1,
         message_maker/3,
         message_handler/4,
         message_size/1]).

-record(state, {actor :: ldb_node_id()}).
-type st() :: #state{}.

%% {crdt, vv, map buffer}
-type stored() :: {term(), vclock(), maps:map(dot(), term())}.

-spec backend_state() -> st().
backend_state() ->
    Actor = ldb_config:id(),
    #state{actor=Actor}.

-spec bottom_entry(term(), st()) -> stored().
bottom_entry(Bottom, _) ->
    VV = vclock:new(),
    DeltaBuffer = maps:new(),
    {Bottom, VV, DeltaBuffer}.

-spec crdt(stored()) -> term().
crdt({CRDT, _, _}) ->
    CRDT.

-spec update(stored(), operation(), st()) -> stored().
update({{Type, _}=CRDT0, VV0, _}=Stored, Operation, #state{actor=Actor}) ->
    {ok, Delta} = Type:delta_mutate(Operation, Actor, CRDT0),
    Dot = vclock:next_dot(Actor, VV0),
    store_delta(Dot, Delta, Stored).

-spec memory(stored()) -> size_metric().
memory({CRDT, VV, DeltaBuffer}) ->
    {M, C} = message_size({dotted_buffer, DeltaBuffer}),
    Alg = M + C + ldb_util:size(vector, VV),
    {Alg, ldb_util:size(crdt, CRDT)}.

-spec message_maker(stored(), ldb_node_id(), st()) -> message().
message_maker({_CRDT, VV, DeltaBuffer}, _, _) ->
    case maps:size(DeltaBuffer) of
        0 ->
            nothing;
        _ ->
            {
                vector,
                VV
            }
    end.

-spec message_handler(message(), ldb_node_id(), stored(), st()) ->
    {stored(), nothing | message()}.
message_handler({vector, RemoteVV}, _From,
                {_, _, DeltaBuffer}=Stored, _) ->

    %% find dots that do not exist in the remote node
    Result = maps:filter(
        fun(Dot, _) -> not vclock:is_element(Dot, RemoteVV) end,
        DeltaBuffer
    ),

    %% send buffer
    Reply = {
        dotted_buffer,
        Result
    },
    {Stored, Reply};

message_handler({dotted_buffer, Buffer}, _From,
                Stored0, _) ->
    Stored = maps:fold(
        fun(Dot, Delta, StoreValueAcc) ->
            store_delta(Dot, Delta, StoreValueAcc)
        end,
        Stored0,
        Buffer
    ),
    {Stored, nothing}.

-spec message_size(message()) -> size_metric().
message_size({dotted_buffer, _}=Buffer) ->
    ldb_scuttlebutt_backend:message_size(Buffer);
message_size({vector, Vector}) ->
    {ldb_util:size(vector, Vector), 0}.

%% @private
store_delta(Dot, Delta, {{Type, _}=CRDT0, VV0, DeltaBuffer0}) ->
    CRDT1 = Type:merge(Delta, CRDT0),
    VV1 = vclock:add_dot(Dot, VV0),
    DeltaBuffer1 = maps:put(Dot, Delta, DeltaBuffer0),
    {CRDT1, VV1, DeltaBuffer1}.
