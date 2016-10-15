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

-module(ldb_config).
-author("Vitor Enes Duarte <vitorenesduarte@gmail.com").

-export([mode/0,
         backend/0,
         store/0,
         peer_service/0]).

%% @doc Returns the enabled mode.
%%      The result can be:
%%          - `state_based'
%%          - `delta_based'
%%          - `pure_op_based'
-spec mode() -> atom().
mode() ->
    state_based.

%% @doc Returns the enabled backend.
-spec backend() -> atom().
backend() ->
    case mode() of
        state_based ->
            ldb_state_based_backend
    end.

%% @doc Returns the enabled store.
-spec store() -> atom().
store() ->
    ldb_ets_store.

%% @doc Returns the enabled peer service.
peer_service() ->
    partisan_default_peer_service_manager.
