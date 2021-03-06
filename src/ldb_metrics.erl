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

-module(ldb_metrics).
-author("Vitor Enes <vitorenesduarte@gmail.com").

-include("ldb.hrl").

%% ldb_metrics callbacks
-export([new/0,
         merge_all/1,
         record_transmission/3,
         record_memory/3,
         record_latency/3,
         record_processing/2]).

-type term_size() :: non_neg_integer().

-type transmission() :: maps:map(timestamp(), {size_metric(), term_size()}).
-type memory() :: maps:map(timestamp(), {size_metric(), size_metric()}).
-type latency() :: maps:map(atom(), list(non_neg_integer())).
-type processing() :: non_neg_integer().

-record(state, {transmission :: transmission(),
                memory :: memory(),
                latency :: latency(),
                processing :: processing()}).
-type st() :: #state{}.

-spec new() -> st().
new() ->
    #state{transmission=maps:new(),
           memory=maps:new(),
           latency=maps:new(),
           processing=0}.

-spec merge_all(list(st())) -> {transmission(), memory(), latency(), processing()}.
merge_all([A, B | T]) ->
    #state{transmission=TransmissionA,
           memory=MemoryA,
           latency=LatencyA,
           processing=ProcessingA} = A,
    #state{transmission=TransmissionB,
           memory=MemoryB,
           latency=LatencyB,
           processing=ProcessingB} = B,
    Transmission = maps_ext:merge_all(
        fun(_, {VA, TA}, {VB, TB}) -> {ldb_util:plus(VA, VB), TA + TB} end,
        TransmissionA,
        TransmissionB
    ),
    Memory = maps_ext:merge_all(
        fun(_, {VA, TA}, {VB, TB}) -> {ldb_util:plus(VA, VB), TA + TB} end,
        MemoryA,
        MemoryB
    ),
    Latency = maps_ext:merge_all(
        fun(_, VA, VB) -> VA ++ VB end,
        LatencyA,
        LatencyB
    ),
    Processing = ProcessingA + ProcessingB,
    H = #state{transmission=Transmission,
               memory=Memory,
               latency=Latency,
               processing=Processing},
    merge_all([H | T]);
merge_all([#state{transmission=Transmission,
                  memory=Memory,
                  latency=Latency,
                  processing=Processing}]) ->
    {Transmission, Memory, Latency, Processing}.

-spec record_transmission(size_metric(), term_size(), st()) -> st().
record_transmission({0, 0}, _, State) ->
    State;
record_transmission(Size, TermSize, #state{transmission=Transmission0}=State) ->
    Timestamp = ldb_util:unix_timestamp(),
    Transmission = update_transmission(Timestamp, Size, TermSize, Transmission0),
    State#state{transmission=Transmission}.

-spec record_memory(size_metric(), term_size(), st()) -> st().
record_memory({0, 0}, _, State) ->
    State;
record_memory(Size, TermSize, #state{memory=Memory0}=State) ->
    Timestamp = ldb_util:unix_timestamp(),
    Memory = update_memory(Timestamp, Size, TermSize, Memory0),
    State#state{memory=Memory}.

-spec record_latency(atom(), non_neg_integer(), st()) -> st().
record_latency(Type, MicroSeconds, #state{latency=Latency0}=State) ->
    Latency = update_latency(Type, MicroSeconds, Latency0),
    State#state{latency=Latency}.

-spec record_processing(processing(), st()) -> st().
record_processing(MicroSeconds, #state{processing=Processing0}=State) ->
    State#state{processing=Processing0 + MicroSeconds}.

update_transmission(Timestamp, Size, TermSize, Transmission0) ->
    maps:update_with(
        Timestamp,
        fun({V, T}) -> {ldb_util:plus(V, Size), T + TermSize} end,
        {Size, TermSize},
        Transmission0
    ).

update_memory(Timestamp, Size, TermSize, Memory0) ->
    maps:update_with(
        Timestamp,
        fun({V, T}) -> {ldb_util:plus(V, Size), T + TermSize} end,
        {Size, TermSize},
        Memory0
    ).

update_latency(Type, MicroSeconds, Latency0) ->
    maps:update_with(
        Type,
        fun(V) -> [MicroSeconds | V] end,
        [MicroSeconds],
        Latency0
    ).
