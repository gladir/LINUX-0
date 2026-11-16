[[ abc == a* ]] && echo m1
[[ abc == "a*" ]] || echo m2
[[ 5 -gt 3 && -n x ]] && echo m3
[[ ! -e /nonexist ]] && echo m4
[[ abc =~ ^a(b)c$ ]] && echo "m5 ${#BASH_REMATCH[@]} ${BASH_REMATCH[0]} ${BASH_REMATCH[1]}"
[[ "a b" =~ ^a\ b$ ]] && echo m6
[[ foo.txt == *.@(txt|md) ]] && echo ext || echo noext
shopt -s extglob
[[ foo.txt == *.@(txt|md) ]] && echo ext2
[[ x == !(y) ]] && echo m7
[[ aaa == +(a) ]] && echo m8
[[ "" == ?(a) ]] && echo m9
[[ ab == a?(b)c ]] || echo m10
x=5; [[ $x -eq 5 ]] && echo eq; [[ $x == 5 ]] && echo seq
[[ a < b ]] && echo lt; [[ b > a ]] && echo gt
[[ -z "" && ( -n a || -n b ) ]] && echo paren
[[ -f /etc/passwd && -r /etc/passwd ]] && echo files
y=; [[ -z $y ]] && echo emptyok
[[ $nonexist == "" ]] && echo unset_ok
if [[ $x -gt 3 ]]; then echo big; elif [[ $x -gt 1 ]]; then echo mid; else echo small; fi
[[ 010 -eq 8 ]] && echo oct
[[ abc != b* ]] && echo ne
case abc in a*) echo cmatch;; esac
case x in @(x|y)) echo cext;; esac
[ "a" = "a" ] && echo oldtest
[[ -v x ]] && echo set; [[ -v nope ]] || echo unset
shopt -u extglob
