{ lib
, buildPythonPackage
, fetchPypi
}:

buildPythonPackage rec {
  pname = "types-psutil";
  version = "5.9.5.20240316";
  format = "setuptools";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-Vjb1cUu5MMZLs0xNR6WdyS+dYQt3i1Nkox2qVYSUSEg=";
  };

  # Module doesn't have tests
  doCheck = false;

  pythonImportsCheck = [
    "psutil-stubs"
  ];

  meta = with lib; {
    description = "Typing stubs for psutil";
    homepage = "https://github.com/python/typeshed";
    license = licenses.asl20;
    maintainers = with maintainers; [ anselmschueler ];
  };
}
