-module(unmatched).
-export([test/0, new/4, increase/3, account/1, oracle/1,
	 true/1, false/1, bad/1,
	 write/2, get/2, %root_hash/1, %add_bet/4,
	 reward/3, delete/2, verify_proof/4,
         dict_add_bet/5, dict_get/2, dict_delete/2,
         serialize/1, make_leaf/3, key_to_int/1,
         deserialize/1]).
-include("../../records.hrl").
%Each account has a tree of oracle bets. Oracle bets are not transferable. Once an oracle is settled, the bets in it can be converted to shares.
-record(unmatched, {account, oracle, true, false, bad}).
%true, false, and bad are the 3 types of shares that can be purchased from an oracle
-define(name, unmatched).
reward(Bet, Correct, NewHeight) ->
    {Positive, _Negative} = 
	case Correct of
	    1->{Bet#unmatched.true,Bet#unmatched.false+Bet#unmatched.bad};
	    2->{Bet#unmatched.false,Bet#unmatched.true+Bet#unmatched.bad};
	    3->{Bet#unmatched.bad,Bet#unmatched.true+Bet#unmatched.false}
	end,
    Positive.
oracle(X) -> X#unmatched.oracle.
account(X) -> X#unmatched.account.
true(X) -> X#unmatched.true.
false(X) -> X#unmatched.false.
bad(X) -> X#unmatched.bad.
increase(X, Type, A) ->
    case Type of
	1 -> X#unmatched{true = X#unmatched.true + A};
	2 -> X#unmatched{false = X#unmatched.false + A};
	3 -> X#unmatched{bad = X#unmatched.bad + A}
    end.
new(Account, Oracle, Type, Amount) ->
    <<_:256>> = Oracle,
    PS = constants:pubkey_size(),
    PS = size(Account),
    true = is_binary(Account),
    {A, B, C} = 
	case Type of
	    1 -> {Amount, 0, 0};
	    2 -> {0, Amount, 0};
	    3 -> {0, 0, Amount}
	end, 
    new(Account, Oracle, A, B, C).
    
new(Account, Oracle, True, False, Bad) ->
    #unmatched{account = Account, oracle = Oracle, true = True, false = False, bad = Bad}.
serialize(X) ->
    HS = constants:hash_size()*8,
    BAL = constants:balance_bits(),
    PS = constants:pubkey_size(),
    PS = size(X#unmatched.account),
    <<_:HS>> = X#unmatched.oracle,
    <<(X#unmatched.account)/binary,
     (X#unmatched.oracle)/binary,
     (X#unmatched.true):BAL,
     (X#unmatched.false):BAL,
     (X#unmatched.bad):BAL>>.
deserialize(B) ->
    %KL = constants:key_length()*8,
    PS = constants:pubkey_size()*8,
    HS = constants:hash_size()*8,
    BAL = constants:balance_bits(),
    <<Account:PS, Oracle:HS, True:BAL, False:BAL, Bad:BAL>> = B,
    #unmatched{true = True, false = False, bad = Bad, oracle = <<Oracle:HS>>, account = <<Account:PS>>}.
dict_write(X, Dict) ->
    Account = X#unmatched.account,
    Oracle = X#unmatched.oracle,
    dict:store({unmatched, {key, Account, Oracle}},
               serialize(X),
               Dict).
write(E, Tree) ->
    K = {key, E#unmatched.account, E#unmatched.oracle},
    Key = key_to_int(K),
    X = serialize(E),
    trie:put(Key, X, 0, Tree, ?name).
dict_get({key, Account, Oracle}, Dict) ->
    true = is_binary(Account),
    io:fwrite(Oracle),
    true = is_binary(Oracle),
    HS = constants:hash_size(),
    HS = size(Oracle),
    PS = constants:pubkey_size(),
    PS = size(Account),
    X = dict:find({unmatched, {key, Account, Oracle}}, Dict),
    case X of
	error -> empty;
        {ok, 0} -> empty;
        {ok, Y} -> deserialize(Y)
    end.
key_to_int({key, Account, Oracle}) -> 
    <<Y:256>> = hash:doit(<<Account/binary, Oracle/binary>>),
    Y.
get(ID, Tree) ->%should probably be generalized to trees module.
    Key = key_to_int(ID),
    {X, Leaf, Proof} = trie:get(Key, Tree, ?name),
    V = case Leaf of
	    empty -> empty;
	    L -> 
		Y = leaf:value(L),
		deserialize(Y)
	end,
    {X, V, Proof}.
dict_delete(Key, Dict) ->
    dict:store({unmatched, Key}, 0, Dict).
delete(Key, Tree) ->
    Int = key_to_int(Key),
    trie:delete(Int, Tree, ?name).
dict_add_bet(Pub, OID, Type, Amount, Dict) ->%changed
    A = accounts:dict_get(Pub, Dict),
    case A of
	empty -> 
	    io:fwrite("account does not exist\n"),
	    io:fwrite(base64:encode(Pub)),
	    io:fwrite("\n"),
	    Dict;
	_ ->
	    X = dict_get({key, Pub, OID}, Dict),
	    Y = case X of
		    empty -> new(Pub, OID, Type, Amount);
		    Bet -> increase(Bet, Type, Amount)
		end, 
	    dict_write(Y, Dict)
    end.
    
%root_hash(A) ->
%    trie:root_hash(?name, A).
make_leaf(Key, V, CFG) ->%should be generalized to trees module.
    leaf:new(key_to_int(Key), V, 0, CFG).
verify_proof(RootHash, Key, Value, Proof) ->%should be generalized to trees module.
    trees:verify_proof(?MODULE, RootHash, Key, Value, Proof).

test() ->
    C = new(keys:pubkey(), <<1:256>>, 3, 100),
    %ID = C#unmatched.id,
    Account = C#unmatched.account,
    OID = C#unmatched.oracle,
    Root0 = constants:root0(),
    ID = {key, Account, OID},
    {_, empty, _} = get(ID, Root0),
    Root = write(C, Root0),
    {Root1, C, Path1} = get(ID, Root),
    {Root2, empty, Path2} = get(ID, Root0),

    true = verify_proof(Root1, ID, serialize(C), Path1),
    true = verify_proof(Root2, ID, 0, Path2),
    test2().
test2() ->
    Pub = keys:pubkey(),
    OID = <<1:256>>,
    C = new(Pub, OID, 3, 100),
    Pub = C#unmatched.account,
    OID = C#unmatched.oracle,
    Key = {key, Pub, OID},
    CFG = trie:cfg(oracle_bets),
    Dict0 = dict:new(),
    Dict1 = dict_write(C, Dict0),
    Account = #acc{balance = 100000, nonce = 0, pubkey = Pub},
    Dict2 = accounts:dict_write(Account, Dict1),
    C = dict_get(Key, Dict2),
    Dict3 = dict_add_bet(Pub, OID, 1, 100, Dict2),
    Bet2 = dict_get(Key, Dict3),
    Bet3 = increase(C, 1, 100),
    Bet2 = Bet3,
    success.
    
    