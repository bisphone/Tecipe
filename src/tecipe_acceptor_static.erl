-module(tecipe_acceptor_static).
-behaviour(supervisor).

-export([start_link/4, start_acceptor/3]).

-export([init/1]).

start_link(SName, Handler, ListeningSock, ListenerOpts) ->
    Pool = proplists:get_value(pool, ListenerOpts),
    Transport = proplists:get_value(transport, ListenerOpts),
    {ok, LName} = tecipe:make_acceptor_lname(SName),
    {ok, AcceptorSup} = supervisor:start_link({local, LName}, ?MODULE,
					      [SName, Handler, Transport, ListeningSock]),
    [{ok, _} = add_acceptor(AcceptorSup) || _ <- lists:seq(1, Pool)],
    {ok, AcceptorSup}.

add_acceptor(Pid) ->
    supervisor:start_child(Pid, []).

init([SName, Handler, Transport, ListeningSock]) ->
    Acceptor = {{tecipe_acceptor_loop, SName},
		{?MODULE, start_acceptor, [Handler, Transport, ListeningSock]},
		permanent,
		3000,
		worker,
		[?MODULE]},

    {ok, {{simple_one_for_one, 10, 1}, [Acceptor]}}.

start_acceptor(Handler, Transport, ListeningSock) ->
    Pid = spawn_link(fun() -> acceptor_loop(Handler, Transport, ListeningSock) end),
    {ok, Pid}.

acceptor_loop(Handler, Transport, ListeningSock) ->
    {ok, Sock} = Transport:accept(ListeningSock),

    Pid = case Handler of
	      {Module, Function, Args} ->
		  spawn(Module, Function, [Transport, Sock, Args]);
	      Function ->
		  spawn(fun() -> Function(Transport, Sock) end)
	  end,

    gen_tcp:controlling_process(Sock, Pid),
    acceptor_loop(Handler, Transport, ListeningSock).
