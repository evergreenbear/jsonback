#!/bin/bash

###
### jsonbackup: quick JSON-based backup script
###

#set -euo pipefail
#IFS=$'\n\t'

## change if needed
bakFile="${BAK_FILE:-$HOME/bin/back.json}"

## colors for fancy output
declare red='\033[0;31m'
declare redbold='\033[01;31m'
declare greenbold='\033[01;32m'
declare cyan='\033[0;36m'
declare cyanbold='\033[01;36m'
declare magenta='\033[0;35m'
declare magentabold='\033[01;35m'
declare bold='\033[0;1m'
declare clear='\033[0m'
declare bluebg='\e[48;5;24m'

## requirements for script to function
neededPkgs=( \
	jq	   \
)

err() {
	printf "${redbold}error:${bold} $1${clear}\n"
	printf "${cyanbold}see ${clear}'${0##*/} help' ${cyanbold}for usage information${clear}\n"
	exit 1
}

usage() {
	printf "$(
		cat <<-EOF
	${greenbold}jsonback${bold}, a quick JSON-based backup script
	${greenbold}commands:${clear}
	lorem ipsum dolor sit amet
	EOF
	)\n"
	exit 1
}

cmdProfile() {
	case "$1" in
		"list"|"l") shift;
			## TODO: allow $0 p [name] to work in addition to $0 p l [name], or standardize
			## TODO: add check to select default profile if none exists
			[[ $(jq '.profiles | length' "$bakFile") -eq 0 ]] && err "no profiles have been registered; create one with ${greenbold}${0##*/} create${clear}"
			
			# show specific profile matching arg if one was provided
			if [[ ! -z "$1"	]]; then
				if ! jq -e --arg name "$1" 'any(.profiles[]; .name == $name)' "$bakFile" 2>&1 >/dev/null; then err "no such profile '$1'"; fi
				
				jq -c --arg name "$1" '.profiles[] | select(.name == $name)' "$bakFile" | while read -r profile; do
					name=$(jq -r '.name' <<< "$profile")
					desc=$(jq -r '.description' <<< "$profile")
					dest=$(jq -r '.destination' <<< "$profile")
					comp=$(jq -r '.compression' <<< "$profile")
					default=$(jq -r '.default' <<< "$profile")

					printf '%b' "${cyanbold}${name}${clear}\n" 
					[[ ! -z "$desc" ]] && printf "  ${bold}about       ${cyanbold}$desc\n"
		   			printf '%b' \
						"  ${bold}default${greenbold}     $default\n" \
				        "  ${bold}compression${bold} $comp\n" \
				        "  ${bold}paths${cyanbold}\n"
			
					jq -r '.paths[]' <<< "$profile" | while read -r path; do
						printf "    -  ${bold}$path${clear}\n"
					done
				done; exit 0		
			fi
			
			# otherwise, show all profiles
			printf "${magentabold}list of configured profiles:\n----------------------------\n${clear}"
			jq -c '.profiles[]' "$bakFile" | while read -r profile; do
				name=$(jq -r '.name' <<< "$profile")
				desc=$(jq -r '.description' <<< "$profile")
				dest=$(jq -r '.destination' <<< "$profile")
				comp=$(jq -r '.compression' <<< "$profile")
				default=$(jq -r '.default' <<< "$profile")

				printf '%b' "\n${cyanbold}${name}${clear}\n" 
				[[ ! -z "$desc" ]] && printf "  ${bold}about       ${cyanbold}$desc\n"
				[[ "$default" == "true" ]] && defcolor="${greenbold}" || defcolor="${redbold}"
		   		printf '%b' \
						"  ${bold}default${defcolor}     $default\n" \
				        "  ${bold}compression${cyanbold} $comp\n" \
				        "  ${bold}paths${clear}\n"
			
				jq -r '.paths[]' <<< "$profile" | while read -r path; do
					printf "   ${cyanbold} -  ${bold}$path${clear}\n"
				done
			done
			printf '\n'
			;;

		"create"|"c") shift;
			printf "${greenbold}creating a new profile\n"

			while true; do
				printf "${bold}Enter a name: ${clear}"; read pName
				[[ -z "$pName" ]] && { printf "${redbold}a name is required${clear}\n"; continue; }
				break
			done
				
			printf "${bold}Add a description, if desired: ${clear}"; read pDesc
		
			while true; do
				printf "${bold}Enter a path for this profile's backups to be stored: ${clear}"; read pDest
				[[ -z "$pDest" ]] && { printf "${redbold}a destination path is required${clear}\n"; continue; }
				[[ "$pDest" =~ ^~ ]] && pDest="${pDest/#\~/$HOME}"
				#pRealDest="$(realpath $pDest)"
				if [[ ! -d "$pDest" ]]; then 
					printf "${redbold}invalid or non-existent path ${bold}$pDest${clear}\n"
					printf "${greenbold}create it? ${bold}(Y/n): ${clear}"; read pDestCreate
					if [[ "${pDestCreate,,}" == "y" ]]; then
						mkdir -p "$pDest"
					else
						continue
					fi
				fi
				printf "${greenbold}backup path set to ${bold}$pDest${clear}\n"
				break
			done

			while [[ -z "$pCompType" ]]; do 
				printf "${bold}Set compression type (zstd, gzip) or disable with 'none':${clear} "; read pCompType
				[[ -z "$pCompType" ]] && { printf "${redbold}a compression type is required${clear}\n"; continue; }
			done
			
			pPaths=()
			while true; do
				printf "${bold}Enter paths to add to profile, either one at a time or space-separted, or press return without input to finish configuration\n${clear}"; read pPathInput
				[[ -z "$pPathInput" ]] && break
				read -ra pRawPaths <<< "$pPathInput"
				for pPath in "${pRawPaths[@]}"; do
					[[ "$pPath" =~ ^~ ]] && pPath="${pPath/#\~/$HOME}"
					pRealPath="$(realpath -m "$pPath")"
					
					if [[ -e "$pRealPath" ]]; then
						pPaths+=("$pRealPath")
						[[ -d "$pRealPath" ]] && printf "${bold}added directory ${greenbold}$pRealPath${clear}\n"
						[[ -f "$pRealPath" ]] && printf "${bold}added file ${greenbold}$pRealPath${clear}\n"
					else
						printf "${redbold}invalid path ${bold}$pRealPath${clear}\n"
					fi
				done
			done

			while true; do
				printf "${greenbold}Set this profile as the active profile? ${bold}(Y/n):${clear} "; read pIsActive
				case "${pIsActive,,}" in
					"y"|"yes") pIsActive="true"; break ;;
					"n"|"no") pIsActive="false"; break ;;
					*) printf "${redbold}invalid input ${bold}$pIsActive${clear}\n"
				esac
			done

			jq --arg name "$pName" \
			--arg desc "$pDesc" \
			--arg dest "$pDest" \
			--arg comp "$pCompType" \
			--arg active "$pIsActive" \
			--argjson paths "$(printf '%s\n' "${pPaths[@]}" | jq -R . | jq -s .)" \
			'
			.profiles |=
			(map(.enabled = "false")) +
			[{
			   	name: $name,
				description: $desc,
				destination: $dest,
				compression: $comp,
				active: $active,
				paths: $paths
			}]
			' "$bakFile" > "$bakFile.tmp" && mv "$bakFile.tmp" "$bakFile"
			printf "${greenbold}Profile ${bold}$pName ${greenbold}has been created!${clear}\n"
			;;
		"modify"|"m")
			## find a TUI way to allow for paths to be modified
		;;
		*) profile="$1"; shift
	esac
}

main() {
	[[ "$#" -lt 1 ]] && usage
   
	# dep check
	for pkg in "${neededPkgs[@]}"; do
		if ! command -v "$pkg" 2>&1 >/dev/null; then err "this script requires $pkg to function; please install it"; fi
	done
	
	# sanity check
	### TODO: auto-create empty template json file if none is found at bakFile

	# arguments
	case "$1" in
		"p"|"profile") shift; cmdProfile "$@" ;;
		"h"|"help"|"--help"|"-h") usage ;;
		*) err "unrecognized command '$1'" ;;
	esac
}

main "$@"
