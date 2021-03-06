%% -------------------------------------------------------------------
%%
%% Copyright (c) 2018 Vitor Enes.  All Rights Reserved.
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

%% @doc A delta-buffer.

-module(ldb_dbuffer).
-author("Vitor Enes <vitorenesduarte@gmail.com>").

-include("ldb.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([new/1,
         seq/1,
         min_seq/1,
         is_empty/1,
         add_inflation/3,
         select/3,
         prune/2,
         size/1,
         show/1]).

-export_type([d/0]).

-record(dbuffer, {avoid_bp :: boolean(),
                  seq :: sequence(),
                  buffer :: orddict:orddict(sequence(), d_entry())}).
-type d() :: #dbuffer{}.

-record(dbuffer_entry, {from :: ldb_node_id(),
                        value :: term()}).
-type d_entry() :: #dbuffer_entry{}.

%% @doc Create new buffer.
-spec new(boolean()) -> d().
new(AvoidBP) ->
    #dbuffer{avoid_bp=AvoidBP,
             seq=0,
             buffer=orddict:new()}.

%% @doc Retrieve seq.
-spec seq(d()) -> sequence().
seq(#dbuffer{seq=Seq}) ->
    Seq.

%% @doc Compute min seq in the buffer.
-spec min_seq(d()) -> sequence().
min_seq(#dbuffer{buffer=[{MinSeq, _}|_]}) ->
    MinSeq;
min_seq(#dbuffer{buffer=[]}) ->
    0.

%% @doc Check if buffer is empty.
-spec is_empty(d()) -> boolean().
is_empty(#dbuffer{buffer=Buffer}) ->
    orddict:size(Buffer) == 0.

%% @doc Add to buffer.
-spec add_inflation(term(), ldb_node_id(), d()) -> d().
add_inflation(CRDT, From, #dbuffer{seq=Seq0,
                                   buffer=Buffer0}=State) ->

    %% create entry
    Entry = #dbuffer_entry{from=From,
                           value=CRDT},

    %% add to buffer
    Buffer = orddict:store(Seq0, Entry, Buffer0),

    %% update seq
    Seq = Seq0 + 1,

    %% update state
    State#dbuffer{seq=Seq, buffer=Buffer}.

%% @doc Select inflations from buffer.
-spec select(ldb_node_id(), sequence(), d()) -> term() | undefined.
select(To, LastAck, #dbuffer{avoid_bp=AvoidBP,
                             buffer=Buffer}) ->
    orddict:fold(
        fun(Seq, #dbuffer_entry{from=From,
                                value={Type, _}=CRDT}, Acc) ->

            case should_send(From, Seq, To, LastAck, AvoidBP) of
                true ->
                    case Acc of
                        undefined -> CRDT; %% if didn't select any until now
                        _ -> Type:merge(CRDT, Acc)
                    end;
                false ->
                    Acc
            end
        end,
        undefined,
        Buffer
    ).

%% @doc Prune from buffer.
-spec prune(sequence(), d()) -> d().
prune(AllAck, #dbuffer{buffer=Buffer0}=State) ->
    Buffer = prune_list(AllAck, Buffer0),
    State#dbuffer{buffer=Buffer}.

%% @doc Prune from the actual buffer.
-spec prune_list(sequence(), orddict:orddict(sequence(), d_entry())) ->
    orddict:orddict(sequence(), d_entry()).
prune_list(AllAck, [{Seq, _}|Rest]) when Seq < AllAck ->
    %% prune and keep pruning
    prune_list(AllAck, Rest);
prune_list(_, L) ->
    %% done pruning
    L.

%% @doc
-spec size(d()) -> non_neg_integer().
size(#dbuffer{buffer=Buffer}) ->
    orddict:fold(
        fun(_, #dbuffer_entry{value=CRDT}, Acc) ->
            %% +1 for the From and Sequence
            Acc + 1 + ldb_util:size(crdt, CRDT)
        end,
        0,
        Buffer
    ).

%% @doc Pretty-print buffer.
-spec show(d()) -> term().
show(#dbuffer{seq=Seq, buffer=Buffer}) ->
    {Seq, lists:sort(orddict:fold(
        fun(EntrySeq, #dbuffer_entry{from=From, value={Type, _}=CRDT}, Acc) ->
            [{EntrySeq, From, Type:query(CRDT)} | Acc]
        end,
        [],
        Buffer
    ))}.

%% @doc Send if not seen (ack <= seq).
%%      If BP, only send if not the origin (from != to)
-spec should_send(ldb_node_id(), sequence(), ldb_node_id(), sequence(), boolean()) ->
    boolean().
should_send(From, Seq, To, LastAck, true) ->
    LastAck =< Seq andalso From =/= To;
should_send(_, Seq, _, LastAck, false) ->
    LastAck =< Seq.


-ifdef(TEST).

dbuffer_test() ->
    AvoidBP = true,
    Buffer0 =  new(AvoidBP),

    Buffer1 = add_inflation({state_gcounter, orddict:from_list([{a, 1}])}, a, Buffer0),
    ToA0 = select(a, 0, Buffer1),
    ToA1 = select(a, 0, Buffer1#dbuffer{avoid_bp=false}),
    ToA2 = select(a, 1, Buffer1),

    Buffer2 = add_inflation({state_gcounter, orddict:from_list([{b, 1}])}, b, Buffer1),
    ToA3 = select(a, 1, Buffer2),
    ToB0 = select(b, 0, Buffer2),

    Buffer3 = prune(1, Buffer2),
    ToA4 = select(a, 1, Buffer3),
    ToA5 = select(a, 2, Buffer3),

    Buffer4 = prune(2, Buffer3),
    %% given that we pruned 2, select 1 shouldn't occur, but:
    ToA6 = select(a, 1, Buffer4),

    Buffer5 = add_inflation({state_gcounter, orddict:from_list([{c, 1}])}, c, Buffer4),
    ToA7 = select(a, 2, Buffer5),
    ToB1 = select(b, 2, Buffer5),
    ToC0 = select(c, 2, Buffer5),

    ?assertEqual(undefined, ToA0),
    ?assertEqual({state_gcounter, orddict:from_list([{a, 1}])}, ToA1),
    ?assertEqual(undefined, ToA2),
    ?assertEqual({state_gcounter, orddict:from_list([{b, 1}])}, ToA3),
    ?assertEqual({state_gcounter, orddict:from_list([{a, 1}])}, ToB0),
    ?assertEqual({state_gcounter, orddict:from_list([{a, 1}])}, ToB0),
    ?assertEqual({state_gcounter, orddict:from_list([{b, 1}])}, ToA4),
    ?assertEqual(undefined, ToA5),
    ?assertEqual(undefined, ToA6),
    ?assertEqual({state_gcounter, orddict:from_list([{c, 1}])}, ToA7),
    ?assertEqual({state_gcounter, orddict:from_list([{c, 1}])}, ToB1),
    ?assertEqual(undefined, ToC0),
    ok.

-endif.
