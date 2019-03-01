(**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

module Request = struct
  type refactor_variant =
    | RENAME of string (* new name *)

  type command =
  | AUTOCOMPLETE of { input: File_input.t; wait_for_recheck: bool option; }
  | CHECK_FILE of {
      input: File_input.t;
      verbose: Verbose.t option;
      force: bool;
      include_warnings: bool;
      wait_for_recheck: bool option;
    }
  | COVERAGE of { input: File_input.t; force: bool; wait_for_recheck: bool option; }
  | BATCH_COVERAGE of { batch : string list; wait_for_recheck: bool option; }
  | CYCLE of { filename: string; }
  | DUMP_TYPES of { input: File_input.t; wait_for_recheck: bool option; }
  | FIND_MODULE of { moduleref: string; filename: string; wait_for_recheck: bool option; }
  | FIND_REFS of {
      filename: File_input.t;
      line: int;
      char: int;
      global: bool;
      multi_hop: bool;
    }
  | FORCE_RECHECK of { files: string list; focus: bool; profile: bool; }
  | GET_DEF of {
      filename: File_input.t;
      line: int;
      char: int;
      wait_for_recheck: bool option;
    }
  | GET_IMPORTS of { module_names: string list; wait_for_recheck: bool option; }
  | GRAPH_DEP_GRAPH of {
      root: string;
      strip_root: bool;
      outfile: string;
    }
  | INFER_TYPE of {
      input: File_input.t;
      line: int;
      char: int;
      verbose: Verbose.t option;
      expand_aliases: bool;
      wait_for_recheck: bool option;
    }
  | REFACTOR of {
      input: File_input.t;
      line: int;
      char: int;
      refactor_variant: refactor_variant;
    }
  | SAVE_STATE of { outfile: Path.t; }
  | STATUS of { client_root: Path.t; include_warnings: bool; }
  | SUGGEST of { input: File_input.t; wait_for_recheck: bool option; }

  let string_of_refactor_variant = function
    | RENAME new_name -> Printf.sprintf "rename(%s)" new_name

  let to_string = function
  | AUTOCOMPLETE { input; wait_for_recheck=_; } ->
    Printf.sprintf "autocomplete %s" (File_input.filename_of_file_input input)
  | CHECK_FILE { input; verbose=_; force=_; include_warnings=_; wait_for_recheck=_; } ->
    Printf.sprintf "check %s" (File_input.filename_of_file_input input)
  | BATCH_COVERAGE { batch=_; wait_for_recheck=_; } ->
      Printf.sprintf "%s" "batch-coverage"
  | COVERAGE { input; force=_; wait_for_recheck=_; } ->
      Printf.sprintf "coverage %s" (File_input.filename_of_file_input input)
  | CYCLE { filename; } ->
      Printf.sprintf "cycle %s" filename
  | GRAPH_DEP_GRAPH _ ->
      Printf.sprintf "dep-graph"
  | DUMP_TYPES { input; wait_for_recheck=_; } ->
      Printf.sprintf "dump-types %s" (File_input.filename_of_file_input input)
  | FIND_MODULE { moduleref; filename; wait_for_recheck=_; } ->
      Printf.sprintf "find-module %s %s" moduleref filename
  | FIND_REFS { filename; line; char; global; multi_hop; } ->
      Printf.sprintf "find-refs %s:%d:%d:%B:%B"
        (File_input.filename_of_file_input filename) line char global multi_hop
  | FORCE_RECHECK { files; focus; profile=_; } ->
      Printf.sprintf
        "force-recheck %s (focus = %b)" (String.concat " " files) focus
  | GET_DEF { filename; line; char; wait_for_recheck=_; } ->
      Printf.sprintf "get-def %s:%d:%d"
        (File_input.filename_of_file_input filename) line char
  | GET_IMPORTS { module_names; wait_for_recheck=_; } ->
      Printf.sprintf "get-imports %s" (String.concat " " module_names)
  | INFER_TYPE { input; line; char; verbose=_; expand_aliases=_; wait_for_recheck=_; } ->
      Printf.sprintf "type-at-pos %s:%d:%d"
        (File_input.filename_of_file_input input) line char
  | REFACTOR { input; line; char; refactor_variant; } ->
      Printf.sprintf "refactor %s:%d:%d:%s"
        (File_input.filename_of_file_input input)
        line
        char
        (string_of_refactor_variant refactor_variant)
  | STATUS { client_root=_; include_warnings=_; } ->
      "status"
  | SUGGEST _ ->
      "suggest"
  | SAVE_STATE { outfile; } ->
      Printf.sprintf "save-state %s" (Path.to_string outfile)

  type command_with_context = {
    client_logging_context: FlowEventLogger.logging_context;
    command: command;
  }
end

module Response = struct

  type lazy_stats = {
    lazy_mode: Options.lazy_mode option;
    checked_files: int;
    total_files: int;
  }
  (* Details about functions to be added in json output *)
  type func_param_result = {
      param_name     : string;
      param_ty       : string;
    }

  type func_details_result = {
      param_tys : func_param_result list;
      return_ty : string;
    }

  (* Results ready to be displayed to the user *)
  type complete_autocomplete_result = {
      res_loc      : Loc.t;
      res_ty       : string;
      res_kind     : Lsp.Completion.completionItemKind option;
      res_name     : string;
      func_details : func_details_result option;
    }

  type autocomplete_response = (
    complete_autocomplete_result list,
    string
  ) result

  type coverage_response = (
    (Loc.t * Coverage.Kind.t) list,
    string
  ) result

  type batch_coverage_response = (
    (File_key.t * Coverage.file_coverage) list,
    string
  ) result

  type dump_types_response = (
    (Loc.t * string) list,
    string
  ) result

  (* name of the symbol, locations where it appears, or None if no symbols were found *)
  type find_refs_success = (string * Loc.t list) option
  type find_refs_response = (find_refs_success, string) result

  type get_def_response = (Loc.t, string) result
  type get_imports_response = Loc.t Nel.t Modulename.Map.t SMap.t * SSet.t
  type infer_type_response = (
    Loc.t * Ty.t option,
    string
  ) result

  type textedit = Loc.t * string
  type refactor_ok = {
    refactor_edits: textedit list;
  }

  type refactor_response = (refactor_ok option, string) result

  type suggest_result =
  | Suggest_Ok of {
      tc_errors: Errors.ConcreteLocPrintableErrorSet.t;
      tc_warnings: Errors.ConcreteLocPrintableErrorSet.t;
      suggest_warnings: Errors.ConcreteLocPrintableErrorSet.t;
      annotated_program: (Loc.t, Loc.t) Flow_ast.program;
    }
  | Suggest_Error of Errors.ConcreteLocPrintableErrorSet.t

  type suggest_response = (
    suggest_result,
    string
  ) result

  type graph_response = (graph_response_subgraph, string) result
  and graph_response_subgraph = (string * string list) list

  type directory_mismatch = {
    server: Path.t;
    client: Path.t;
  }

  type status_response =
  | DIRECTORY_MISMATCH of directory_mismatch
  | ERRORS of {errors: Errors.ConcreteLocPrintableErrorSet.t; warnings: Errors.ConcreteLocPrintableErrorSet.t}
  | NO_ERRORS
  | NOT_COVERED

  type check_file_response = status_response

  type find_module_response = File_key.t option

  type response =
  | AUTOCOMPLETE of autocomplete_response
  | CHECK_FILE of check_file_response
  | COVERAGE of coverage_response
  | BATCH_COVERAGE of {response: batch_coverage_response; lazy_stats: lazy_stats }
  | CYCLE of graph_response
  | GRAPH_DEP_GRAPH of (unit, string) result
  | DUMP_TYPES of dump_types_response
  | FIND_MODULE of find_module_response
  | FIND_REFS of find_refs_response
  | GET_DEF of get_def_response
  | GET_IMPORTS of get_imports_response
  | INFER_TYPE of infer_type_response
  | REFACTOR of refactor_response
  | STATUS of { status_response: status_response; lazy_stats: lazy_stats }
  | FORCE_RECHECK of Profiling_js.finished option
  | SUGGEST of suggest_response
  | SAVE_STATE of (unit, string) result

  let to_string = function
  | AUTOCOMPLETE _ -> "autocomplete response"
  | CHECK_FILE _ -> "check_file response"
  | COVERAGE _ -> "coverage response"
  | BATCH_COVERAGE _ -> "batch-coverage response"
  | CYCLE _ -> "cycle response"
  | GRAPH_DEP_GRAPH _ -> "dep-graph response"
  | DUMP_TYPES _ -> "dump_types response"
  | FIND_MODULE _ -> "find_module response"
  | FIND_REFS _ -> "find_refs response"
  | GET_DEF _ -> "get_def response"
  | GET_IMPORTS _ -> "get_imports response"
  | INFER_TYPE _ -> "infer_type response"
  | REFACTOR _ -> "refactor response"
  | STATUS _ -> "status response"
  | FORCE_RECHECK _ -> "force_recheck response"
  | SUGGEST _ -> "suggest response"
  | SAVE_STATE _ -> "save_state response"
end
