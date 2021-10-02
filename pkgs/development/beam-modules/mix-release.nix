{ stdenv, lib, elixir, erlang, findutils, hex, rebar, rebar3, fetchMixDeps, makeWrapper, git, ripgrep }:

{ pname
, version
, src
, nativeBuildInputs ? [ ]
, meta ? { }
, enableDebugInfo ? false
, mixEnv ? "prod"
, compileFlags ? [ ]
  # mix fixed output derivation dependencies
, mixFodDeps ? null
  # mix dependencies generated by mix2nix
  # this assumes each dependency is built by buildMix or buildRebar3
  # each dependency needs to have a setup hook to add the lib path to $ERL_LIBS
  # this is how mix will find dependencies
, mixNixDeps ? { }
, ...
}@attrs:
let
  # remove non standard attributes that cannot be coerced to strings
  overridable = builtins.removeAttrs attrs [ "compileFlags" "mixNixDeps" ];
in
assert mixNixDeps != { } -> mixFodDeps == null;
stdenv.mkDerivation (overridable // {
  # rg is used as a better grep to search for erlang references in the final release
  nativeBuildInputs = nativeBuildInputs ++ [ erlang hex elixir makeWrapper git ripgrep ];
  buildInputs = builtins.attrValues mixNixDeps;

  MIX_ENV = mixEnv;
  MIX_DEBUG = if enableDebugInfo then 1 else 0;
  HEX_OFFLINE = 1;
  DEBUG = if enableDebugInfo then 1 else 0; # for Rebar3 compilation
  # the api with `mix local.rebar rebar path` makes a copy of the binary
  # some older dependencies still use rebar
  MIX_REBAR = "${rebar}/bin/rebar";
  MIX_REBAR3 = "${rebar3}/bin/rebar3";

  postUnpack = ''
    export HEX_HOME="$TEMPDIR/hex"
    export MIX_HOME="$TEMPDIR/mix"

    # Rebar
    export REBAR_GLOBAL_CONFIG_DIR="$TEMPDIR/rebar3"
    export REBAR_CACHE_DIR="$TEMPDIR/rebar3.cache"

    ${lib.optionalString (mixFodDeps != null) ''
      # compilation of the dependencies will require
      # that the dependency path is writable
      # thus a copy to the TEMPDIR is inevitable here
      export MIX_DEPS_PATH="$TEMPDIR/deps"
      cp --no-preserve=mode -R "${mixFodDeps}" "$MIX_DEPS_PATH"
    ''
    }

  '' + (attrs.postUnpack or "");

  configurePhase = attrs.configurePhase or ''
    runHook preConfigure

    ${./mix-configure-hook.sh}
    # this is needed for projects that have a specific compile step
    # the dependency needs to be compiled in order for the task
    # to be available
    # Phoenix projects for example will need compile.phoenix
    mix deps.compile --no-deps-check --skip-umbrella-children

    runHook postConfigure
  '';

  buildPhase = attrs.buildPhase or ''
    runHook preBuild

    mix compile --no-deps-check ${lib.concatStringsSep " " compileFlags}

    runHook postBuild
  '';


  installPhase = attrs.installPhase or ''
    runHook preInstall

    mix release --no-deps-check --path "$out"

    runHook postInstall
  '';

  # Stripping of the binary is intentional
  # even though it does not affect beam files
  # it is necessary for NIFs binaries
  postFixup = ''
    if [ -e "$out/bin/${pname}.bat" ]; then # absent in special cases, i.e. elixir-ls
      rm "$out/bin/${pname}.bat" # windows file
    fi
    # contains secrets and should not be in the nix store
    # TODO document how to handle RELEASE_COOKIE
    # secrets should not be in the nix store.
    # This is only used for connecting multiple nodes
    if [ -e $out/releases/COOKIE ]; then # absent in special cases, i.e. elixir-ls
      rm $out/releases/COOKIE
    fi
    # removing unused erlang reference from resulting derivation to reduce
    # closure size
    if [ -e $out/erts-* ]; then
      echo "ERTS found in $out - removing references to erlang to reduce closure size"
      # there is a link in $out/erts-*/bin/start always
      # TODO:
      # sometimes there are links in dependencies like bcrypt compiled binaries
      # at the moment those are not removed since substituteInPlace will
      # error on binaries
      for file in $(rg "${erlang}/lib/erlang" "$out" --files-with-matches); do
        echo "removing reference to erlang in $file"
        substituteInPlace "$file" --replace "${erlang}/lib/erlang" "$out"
      done
    fi
  '';

  # TODO investigate why the resulting closure still has
  # a reference to erlang.
  # uncommenting the following will fail the build
  # disallowedReferences = [ erlang ];
})
