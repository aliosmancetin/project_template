import os
import json
import subprocess
import sys

def update_meta_info(main_directory, subdirectories, new_index_seq_hash, update_json_dir):
    for subdir in subdirectories:
        aux_info_path = os.path.join(main_directory, subdir, 'aux_info')
        meta_info_path = os.path.join(aux_info_path, 'meta_info.json')
        if os.path.exists(meta_info_path):
            output_file = os.path.join(aux_info_path, 'meta_info_with_seq_hash.json')
            update_script_path = os.path.join(update_json_dir, 'update_json.py')
            subprocess.run([sys.executable, update_script_path, meta_info_path, output_file, new_index_seq_hash])

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='Update index_seq_hash in JSON files within subdirectories')
    parser.add_argument('main_directory', type=str, help='Full path to the main directory')
    parser.add_argument('subdirectories', nargs='+', type=str, help='List of subdirectory names')
    parser.add_argument('--new_index_seq_hash', type=str, required=True, help='New value for index_seq_hash')
    parser.add_argument('--update_json_dir', type=str, required=True, help='Directory path of update_json.py script')
    args = parser.parse_args()

    update_meta_info(args.main_directory, args.subdirectories, args.new_index_seq_hash, args.update_json_dir)


# usage: python update_meta_info.py /full/path/to/main_directory subdirectory1 subdirectory2 --new_index_seq_hash YOUR_NEW_INDEX_SEQ_HASH --update_json_dir /full/path/to/update_json_directory


