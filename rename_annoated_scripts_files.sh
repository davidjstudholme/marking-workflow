for f in *.*; do
  new=$(echo "$f" | sed -E 's/^[0-9]+_(X[0-9a-f]+)_1_[0-9a-f]+\.(pdf|pptx)$/\1.\2/')
  if [ "$new" != "$f" ]; then
    mv -i -- "$f" "$new"
  fi
done
