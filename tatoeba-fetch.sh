#! /bin/bash

# File description (user_languages)
#   Indicates the self-reported skill levels of members in individual languages.
# Fields and structure
#   Lang [tab] Skill level [tab] Username [tab] Details

# File description (sentences_base)
#   Each sentence is listed as original or a translation of another. The "base" field can have the following values:
#       zero: The sentence is original, not a translation of another.
#       greater than zero: The id of the sentence from which it was translated.
#       \N: Unknown (rare).
# Fields and structure
#   Sentence id [tab] Base field

for file in "user_languages" "sentences_base"; do
    echo "$file.csv"
    if [[ ! -e "$file.csv" ]]; then
        curl "https://downloads.tatoeba.org/exports/$file.tar.bz2" | tar -xj;
    fi
done

# File description
#   Contains all the sentences available under CC0.
# Fields and structure
#   Sentence id [tab] Lang [tab] Text [tab] Username [tab] Date added [tab] Date last modified
for lang in "spa" "swe"; do
    file="${lang}_sentences_detailed.tsv"
    echo "${file}"
    if [[ ! -e "${file}" ]]; then
        curl "https://downloads.tatoeba.org/exports/per_language/${lang}/${file}.bz2" | bunzip2 -c > ${file};
    fi
done
