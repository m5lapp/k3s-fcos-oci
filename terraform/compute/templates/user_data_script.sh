#!/bin/sh
# IMPORTANT: Do not change the line above, it must be exactly that for this
# script to be run by cloud-init.
#   https://cloudinit.readthedocs.io/en/latest/explanation/format.html#id3

sudo dnf install -y podman

# Here we decode the base64 encoded JSON map containing the Butane files for
# each of the k3s Nodes and save each one into a file with the name of the key
# in the JSON map as the file name, then run the butane command on it to
# generate the Ignition file.
echo ${butane_file_map} | \
    base64 -d | \
    jq -cr 'keys[] as $k | "\($k)\n\(.[$k])"' |
    while read -r BUT_FILE_NAME; do
        BUT_FILE_PATH="/home/opc/$${BUT_FILE_NAME}"
        IGN_FILE_PATH="$${BUT_FILE_PATH}.ign"
        read -r BUT_FILE_CONTENT;

        sudo printf "%s\n" "$(echo $${BUT_FILE_CONTENT} | base64 -d)" > "$${BUT_FILE_PATH}";
        sudo chown opc:opc $${BUT_FILE_PATH}
        sudo chmod 644 $${BUT_FILE_PATH}

        # Convert the Butane YAML file to an Ignition file.
        podman container run --interactive \
            --rm quay.io/coreos/butane:release \
            --pretty --strict < $${BUT_FILE_PATH} > $${IGN_FILE_PATH}

        sudo chown opc:opc $${IGN_FILE_PATH}
        sudo chmod 644 $${IGN_FILE_PATH}
    done

