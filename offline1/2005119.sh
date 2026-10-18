#!/bin/bash

if [ $# -lt 2 ]; then
    echo "Usage: $0 -i sample_input.txt"
    exit 1
fi

input_file="$2"

if [ ! -f "$input_file" ]; then
    echo "Input file '$input_file' does not exist!"
    exit 1
fi

read_file_value() {
    sed -n "${1}p" "$input_file" | tr -d '[:space:]'
}

read_file_value_raw() {
    sed -n "${1}p" "$input_file"
}

# Read values from the input file
archive_status=$(read_file_value 1)
allowed_formats=$(read_file_value_raw 2)
allowed_languages=$(read_file_value_raw 3)
total_marks=$(read_file_value 4)
output_penalty=$(read_file_value 5)
working_directory=$(read_file_value 6)
id_range=$(read_file_value_raw 7)
expected_output_location=$(read_file_value 8)
submission_penalty=$(read_file_value 9)
plagiarism_file_location=$(read_file_value 10)
plagiarism_penalty=$(read_file_value 11)


if [[ "$archive_status" != "true" && "$archive_status" != "false" ]]; then
    echo "Error: First line should only be 'true' or 'false'."
    exit 1
fi

if ! [[ "$total_marks" =~ ^[0-9]+$ ]]; then
    echo "Error: Total marks should be a number."
    exit 1
fi

if ! [[ "$output_penalty" =~ ^[0-9]+$ ]]; then
    echo "Error: Output penalty should be a number."
    exit 1
fi


if [[ ! "$working_directory" =~ ^/ ]]; then
    echo "Error: Working directory should be a valid path."
    exit 1
fi

# Extract student ID range
start_id=$(echo "$id_range" | cut -d ' ' -f 1)
end_id=$(echo "$id_range" | cut -d ' ' -f 2)

if ! [[ "$start_id" =~ ^[0-9]+$ && "$end_id" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid student ID range. Should be two numbers separated by space."
    exit 1
fi


if [[ ! "$expected_output_location" =~ ^/ ]]; then
    echo "Error: Expected output location should be a valid path."
    exit 1
fi


if ! [[ "$submission_penalty" =~ ^[0-9]+$ ]]; then
    echo "Error: Submission penalty should be a number."
    exit 1
fi

if [[ ! "$plagiarism_file_location" =~ ^/ ]]; then
    echo "Error: Plagiarism file location should be a valid path."
    exit 1
fi

if ! [[ "$plagiarism_penalty" =~ ^[0-9]+$ ]]; then
    echo "Error: Plagiarism penalty should be a number."
    exit 1
fi

if [[ -z "$allowed_formats" || ! "$allowed_formats" =~ ^(zip|rar|tar)([[:space:]](zip|rar|tar))*$ ]]; then
    echo "Error: Allowed formats should be a space-separated list of 'zip', 'rar', or 'tar'."
    exit 1
fi

if [[ -z "$allowed_languages" || ! "$allowed_languages" =~ ^(c|cpp|python|sh)([[:space:]](c|cpp|python|sh))*$ ]]; then
    echo "Error: Allowed languages should be a space-separated list of 'c', 'cpp', 'python', or 'sh'."
    exit 1
fi

echo id, marks, marks_deducted, total_marks, remarks > marks.csv

mkdir -p issues checked
rm -rf issues/* checked/*

output_comparison() {
    local output="$1"
    local expected_output="$2"
    local penalty=0
    local mismatch_found=false

    while IFS= read -r expected_line; do
        if ! grep -qF "$expected_line" "$output"; then
            ((penalty += output_penalty))
            mismatch_found=true
        fi
    done < "$expected_output"

    if [ "$mismatch_found" = true ]; then
        echo "Output mismatch detected, penalty: $penalty"
    fi

    return $penalty
}


plagiarized_ids=()

if [ -f "$plagiarism_file_location" ]; then 
    #cat -v "$plagiarism_file_location"

    content=$(<"$plagiarism_file_location")

    for id in $content; do
        id=$(echo "$id" | xargs)

        if [ -n "$id" ]; then
            plagiarized_ids+=("$id")
        fi
    done

    echo "Plagiarized IDs:"
    if [ ${#plagiarized_ids[@]} -eq 0 ]; then
        echo "No IDs found in the file."
    else
        for id in "${plagiarized_ids[@]}"; do
            echo "$id"
        done
    fi
else
    echo "Plagiarism file '$plagiarism_file_location' does not exist!"
fi



# Process each student submission
for submission in "$working_directory"/*; do
    student_id=$(basename "$submission" | cut -d '.' -f 1)

    if ! [[ "$student_id" =~ ^[0-9]+$ ]]; then
        continue
    fi

    if (( student_id >= start_id && student_id <= end_id )); then
        marks=$total_marks
        deduction=0
        remarks=""

        if [[ " ${plagiarized_ids[@]} " =~ " ${student_id} " ]]; then
            ((deduction += plagiarism_penalty))
            ((marks -= deduction))
            remarks="plagiarism detected"
             echo "$student_id,$marks,$deduction,$total_marks,$remarks" >> marks.csv
        fi

        if [ "$archive_status" == "true" ]; then
            has_folder=false
            if [[ -d "$submission" ]]; then
                has_folder=true
                echo "submission is a folder, not an archived file."
                remarks="issue case #1"
                ((deduction += submission_penalty))
                ((marks -= deduction))
                echo "$student_id,$marks,$deduction,$total_marks,$remarks" >> marks.csv
            fi

            if [[ "$has_folder" == "false" ]]; then
                extract="${submission##*.}"
                file_name=$(basename "$submission")

                if [[ ! $allowed_formats =~ $extract ]]; then
                    ((deduction += submission_penalty))
                    ((marks -= deduction))
                    echo "The submitted archive format is not allowed"
                    remarks="issue case #2"
                    mv "$submission" "issues/$student_id"
                    echo "$student_id,$marks,$deduction,$total_marks,$remarks" >> marks.csv
                    continue
                fi

                mkdir "$working_directory/$student_id"
                if [[ "$extract" == "zip" ]]; then
                    unzip -q "$submission" -d "$working_directory/"
                elif [[ "$extract" == "rar" ]]; then
                    unrar x "$submission" "$working_directory/" >/dev/null
                elif [[ "$extract" == "tar" ]]; then
                    tar xf "$submission" -C "$working_directory/"
                fi

                submission_directory="$working_directory/$student_id"
            fi
            
        else
            # Handle non-archived files directly
            if [[ ! $allowed_formats =~ $extension ]]; then
                ((deduction += submission_penalty))
                ((marks -= deduction))
                echo "submitted archive format is not allowed"
                remarks="issue case #2"
                mv "$submission" "issues/$student_id"
                echo "$student_id,$marks,$deduction,$total_marks,$remarks" >> marks.csv
                continue
            fi

            # Create a directory for the student submission
            mkdir -p "$working_directory/$student_id"
            cp "$submission" "$working_directory/$student_id/"
            submission_directory="$working_directory/$student_id"
        fi

        # Check for the correct file (matching student ID)
        file_matched=false
        for file in "$working_directory/$student_id/"*; do
            file_name=$(basename "$file" | cut -d '.' -f 1)
            extension="${file##*.}"

            if [[ "$file_name" == "$student_id" &&  $allowed_languages =~ $extension ]]; then
                file_matched=true
                break
            fi
        done

        if [ "$file_matched" = true ]; then
            output_directory="$submission_directory/${student_id}_output"
            mkdir -p "$output_directory"
            output_file="$output_directory/${student_id}_output.txt"

            case "$extension" in
                "c")
                    gcc "$file" -o "$submission_directory/${student_id}_exec"
                    echo "C file: $file"
                    if [ $? -eq 0 ]; then
                        "$submission_directory/${student_id}_exec" > "$output_file"
                    else
                        echo "Compilation error for $student_id" >> marks.csv
                        continue
                    fi
                    ;;
                "cpp")
                    g++ "$file" -o "$submission_directory/${student_id}_exec"
                    if [ $? -eq 0 ]; then
                        "$submission_directory/${student_id}_exec" > "$output_file"
                    else
                        echo "Compilation error for $student_id" >> marks.csv
                        continue
                    fi
                    ;;
                "py")
                    python3 "$file" > "$output_file"
                    ;;
                "sh")
                    bash "$file" > "$output_file"
                    ;;
            esac

            # Run output comparison after the execution for all cases
            output_comparison "$output_file" "$expected_output_location"
            output_deductions=$?
            ((deduction += output_deductions))
            ((marks = total_marks - deduction))

            if [[ "$has_folder" == "false" ]]; then
                mv "$submission_directory" "checked/$student_id"
                echo "$student_id,$marks,$deduction,$total_marks,Valid Submission" >> marks.csv
            fi
            
        else
           if [[ "$file_name" != "$student_id" ]]; then
                echo "Extracted folder name does not match the student ID"
                remarks="issue case #4"
                ((deduction += submission_penalty))
                ((marks -= deduction))
                echo "$student_id,$marks,$deduction,$total_marks,$remarks" >> marks.csv

            else
                echo "Programming language not allowed"
                remarks="issue case #3"
                mv "$submission_directory" "issues/$student_id"
                ((deduction += submission_penalty))
                ((marks -= deduction))
                echo "$student_id,$marks,$deduction,$total_marks,$remarks" >> marks.csv

            fi
        fi
    else
        remarks="issue case #5"
        marks=0  
        deduction=0  

        echo "$student_id,$marks,$deduction,$total_marks,$remarks" >> marks.csv
        echo "$student_id not in valid range"
    
    fi
done
