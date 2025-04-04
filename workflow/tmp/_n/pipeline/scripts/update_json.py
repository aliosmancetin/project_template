import json
import argparse
import os

def update_json(json_file, new_json_file, index_seq_hash):
    with open(json_file, 'r') as f:
        data = json.load(f)
    
    data['index_seq_hash'] = index_seq_hash

    with open(new_json_file, 'w') as f:
        json.dump(data, f, indent=4)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Update index_seq_hash in JSON file')
    parser.add_argument('json_file', type=str, help='Path to the JSON file')
    parser.add_argument('new_json_file', type=str, help='Path to the new JSON file')
    parser.add_argument('index_seq_hash', type=str, help='New value for index_seq_hash')
    args = parser.parse_args()

    update_json(args.json_file, args.new_json_file, args.index_seq_hash)


# usage: python update_json.py input.json output.json new_index_seq_hash_value

