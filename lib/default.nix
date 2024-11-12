lib: {
  asciidoctor = {
    /*
    Recursively merges a list of attribute sets, similar to `lib.mkMerge`.

    Unlike `lib.mkMerge`, this returns a merged attribute set.

    # Type

    ```
    mergeAttrsMkMerge :: [AttrSet] -> AttrSet
    ```

    # Throws

    Throws an error if elements to be merged have different types.

    # Examples

    ```nix
    mergeAttrsMkMerge [
      {
        attrset = {
          attrset = {
            int = 0;
            list = [ 1 2 3 ];
          };
        };

        int = 4;
        list = [ 5 6 7 ];
      }
      {
        attrset = {
          attrset = {
            bool = false;
            int = 1;
          };
        };

        int = 1;
        list = [ 7 8 9 ];
      }
    ]
    => {
      attrset = {
        attrset = {
          bool = false;
          int = 1;
          list = [ 1 2 3 ];
        };
      };

      int = 1;
      list = [ 5 6 7 8 9 ];
    }

    mergeAttrsMkMerge [
      { int = 0; }
      { int = null; }
    ]
    => error: cannot merge different types: int and null
    ```
    */
    mergeAttrsMkMerge = lib.fix (
      self:
        builtins.zipAttrsWith (
          _: values: let
            expectedType = lib.last valueTypes;

            findFirst =
              lib.findFirst
              (type: type != expectedType)
              null
              valueTypes;

            last = lib.last values;
            valueTypes = map builtins.typeOf values;
          in
            lib.throwIf
            (findFirst != null)
            "cannot merge different types: ${findFirst} and ${expectedType}"
            (
              if builtins.isAttrs last
              then self values
              else if builtins.isList last
              then lib.unique (builtins.concatLists values)
              else last
            )
        )
    );
  };
}
