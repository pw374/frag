(***********************************************************************)
(* Meta Pre Processor, a language blender                              *)
(* (c) 2013 by Philippe Wang <philippe.wang@cl.cam.ac.uk>              *)
(* Licence : CeCILL-B                                                  *)
(* http://www.cecill.info/licences/Licence_CeCILL-B_V1-en.html         *)
(***********************************************************************)

open Mpp_charstream
open Mpp_init

let rec preprocess (charstream: charstream) out =
  assert(!open_token <> "");
  (* assert(!close_token <> ""); *)
  assert(!endline_comments_token <> "");
  assert(!open_comments_token <> "");
  (* assert(!close_comments_token <> ""); *)
  
  (* entry point *)
  let rec loop (): unit =
    begin
      if match_token !open_token charstream then
        open_token_action()
      else if match_token !close_token charstream then
        close_token_action()
      else if match_token !endline_comments_token charstream then
        endline_comments_token_action()
      else if match_token !open_comments_token charstream then
        open_comments_token_action()
      else if match_token !close_comments_token charstream then
        close_comments_token_action()
      else
        default(charstream.take())
    end

  (* default action *)
  and default = function
    | None -> ()
    | Some c ->
        (* Printf.eprintf "<%s>%!" (Char.escaped c); *)
        output_char out c;
        flush out;
        loop()

  (* new block *)
  and open_token_action () =
    let _action_nested_option =
      match charstream.take() with
        | Some '\\' -> `Not_Nested
        | Some c -> charstream.push c; `Nested
        | None ->
            parse_error
              ~msg:"No characters left to read right after an opening! (1)" 
              (charstream.where());
            exit 1
    in
    let () = 
      if debug then 
        Printf.eprintf "peek<%s>\n%!"
          (String.escaped (charstream_peek ~n:20 charstream))
    in
    let block_name = (* block_name: syntactic "tool" *)
      match charstream.take() with
        | None ->
            parse_error
              ~msg:"No characters left to read right after an opening! (2)" 
              (charstream.where());
            exit 1
        | Some (' ' | '\t') ->
            None
        | Some c ->
            charstream.push c;
            let () = 
              if debug then Printf.eprintf "peek<%s>\n%!"
                (String.escaped (charstream_peek ~n:20 charstream))
            in
              Some (read_until ~failsafe:true ' ' charstream)
    in
    let () = eat space_chars charstream in
    let block_start_location = charstream.where() in
    let block_contents =
      (* the contents of the block *)
      match block_name with
        | Some name -> 
            if debug then Printf.eprintf "name=<%s>%!" name;
            read_until_word charstream (name^ !close_token)
        | None -> read_until_word charstream (!close_token)
    in
    let charstream = () in let _ = charstream in (* ~> to prevent its use afterwards *)
    let blockcharstream =
      (* the contents of the block is converted into a charstream *)
      charstream_of_string ~location:(block_start_location) block_contents
    in
    let action_name : string = (* name of the action *)
      eat space_chars blockcharstream;
      read_until_one_of
        ~failsafe:true
        space_chars
        (* ~exclude:newline_chars *)
        ~expect:"Zero or more spaces, and then an action name."
        blockcharstream
    in
    let action_arguments : string = (* action arguments *)
      match blockcharstream.take() with
        | Some c ->
            blockcharstream.push c;
            read_until_one_of ~failsafe:true newline_chars blockcharstream
        | None ->
            ""
    in
      Mpp_actions.exec action_name action_arguments blockcharstream out;
      loop ()

  (* Closing a block that hasn't been opened is wrong. *)
  and close_token_action() =
    parse_error ~msg:"Closing unopened block." (charstream.where());
    exit 1

  (* Just ignore what has to be ignored. *)
  and endline_comments_token_action() =
    let _l = read_until_one_of newline_chars charstream in
      if debug then Printf.eprintf  "comments: <%s>\n%!" _l;
      loop()

  (* New comment block. *)
  and open_comments_token_action() = 
    let _c = read_until_word charstream (!close_comments_token) in
      if debug then Printf.eprintf  "comments: <%s>\n%!" _c;
      loop()

  (* Closing a comment block that hasn't been opened is wrong. *)
  and close_comments_token_action() = 
    parse_error ~msg:"Closing unopened comments block." (charstream.where());
    exit 1
  in 
    loop()



let init() =
  (* This is here because the input builtin needs to access the
     preprocess function.  *)
  let builtin__input =
    Mpp_actions.Function(fun arg cs out ->
      let x = open_in arg in
        cs.insert (charstream_of_inchannel arg x);
        preprocess cs out;
        close_in x
    )
  in
    Mpp_actions.register "input" builtin__input "Input and process a file."

let _ = 
  let () = init() in
  let l = Array.length Sys.argv in
  let overwrite = ref false in
  let continue = ref false in
  let defaultoutput = ref "" in
  let at_least_one_file_processed = ref false in
  let process_one_file filename =
    if not(Sys.file_exists filename) then
      begin
        if !continue then
          ()
        else
          Printf.eprintf "Error: file <%s> does not exist, I will stop. You might want to use -continue.\n%!"
            filename
      end
    else
      if
        try Filename.chop_extension filename ^ ".mpp" = filename
        with Invalid_argument _ -> false
      then
        begin
          let outputfilename =
            if !defaultoutput = "" then
              Filename.chop_extension filename 
            else
              !defaultoutput
          in
            if outputfilename <> "/dev/stdout" && Sys.file_exists outputfilename && not !overwrite then
              begin
                Printf.eprintf "Warning: file <%s> already exists, I won't overwrite it. You might want to use -overwrite.\n%!"
                  outputfilename
              end
            else
              begin
                let out = open_out_gen [Open_wronly;Open_creat;Open_trunc;Open_binary] 0o640 outputfilename in
                  preprocess (charstream_of_inchannel filename (open_in filename)) out;
                  at_least_one_file_processed := true
              end
        end
      else
        begin
          Printf.eprintf "Warning: filename <%s> does not have .mpp extension. So I'll ouput on stdout.\n%!" filename;
          preprocess (charstream_of_inchannel filename (open_in filename)) stdout;
          at_least_one_file_processed := true
        end
  in
    try
      if l > 1 then
        begin
          let aligned =
            Arg.align [
              "-o", Arg.Set_string(defaultoutput), "filename Output to filename instead of standard option.";
              "-overwrite", Arg.Set(overwrite), " Overwrite existing destination files.";
              "-ow", Arg.Set(overwrite), " Alias for -overwrite.";
              "-continue", Arg.Set(continue), " Continue even if an input file doesn't exist.";
              "-c", Arg.Set(continue), " Alias for -continue.";
              "-ine", Arg.Set(ignore_non_existing_commands), " Ignore non existing commands instead of stopping. (Default is to stop.)";
              "-see", Arg.Set(Mpp_actions.stop_on_exec_error), " Stop if an error has occurred when executing an external command. (Default is not to stop.)";
              "-builtins", Arg.Unit(Mpp_actions.list_builtins), " List builtins.";
              "-setopentoken", Arg.Set_string(open_token), "token Set open token.";
              "-setclosetoken", Arg.Set_string(close_token), "token Set close token.";
              "-setopencomments", Arg.Set_string(open_comments_token), "token Set open comments token.";
              "-setclosecomments", Arg.Set_string(close_comments_token), "token Set close comments token.";
              "-setendlinecomments", Arg.Set_string(endline_comments_token), "token Set endline comments token.";
              "-set", Arg.String(fun s ->
                                    let cs = charstream_of_string s in 
                                    let vn = read_until_one_of (Mpp_charset.of_list ['='; ' ';'\t']) cs in
                                    let _ = cs.take() in
                                      Mpp_variables.Variable.set (vn ^ " " ^ string_of_charstream cs) (charstream_of_string "") stdout),
              "x=s Sets variable x to s (if you know how, you can use a space instead of =).";
              "--", Arg.Rest(process_one_file), " If you use this parameter, all remaining arguments are considered as file names.";
            ]
          in
(*           let aligned = *)
(*             let rec loop = function *)
(*               | (("-set" as o), a, s) :: rest -> (o, a, (s.[2] <- ' ' ;s)) :: loop rest *)
(*               | (o,a,s) :: rest -> (o,a,s) :: loop rest *)
(*               | [] -> [] *)
(*             in loop aligned *)
(*           in  *)
            Arg.parse
              aligned
              process_one_file
              ("Usage: " ^ Sys.argv.(0) ^ " [-options] [filename1.ext.mpp ... filenameN.ext.mpp]
~ If a file name doesn't have .mpp extension, it will output on stdout.
~ If a file already exists, it won't be overwritten unless you use -overwrite.
~ If you want to overwrite only certain files, you should invoke this programme separately.
~ If you don't give any file name, it will use standard input (/dev/stdin).
~ This software does not care about characters encoding, hence it performs no conversion at all.
~ As of May, 13th, 2013, this software is still under development. Please feel free to email pw374@cl.cam.ac.uk if you find any bug.

List of options:")
        end;

      if not !at_least_one_file_processed then
        preprocess (charstream_of_inchannel "/dev/stdin" stdin) stdout;
    with e ->
      if debug then Printexc.print_backtrace stderr;
      if debug then Printf.eprintf "Exception raised: <%s>\n%!" (Printexc.to_string e);
      Pervasives.exit 1






