
%if 0%{?qubes_builder}
%define _sourcedir %(pwd)
%endif

#%define _unpackaged_files_terminate_build 0
%define variant pvops.qubes
%define plainrel %(cat rel)
%define rel %{plainrel}.%{variant}
%define version %(cat version)

Name:		kernel-devel
Version:	%{version}
Release:	%{rel}
Epoch:      1000
Summary:        Development files necessary for building kernel modules

Group:          Development/Sources
License:        GPL v2 only
Url:            http://www.kernel.org/

%description
This package contains files necessary for building kernel modules (and
kernel module packages) against the pvops flavor of the kernel.

%prep
echo "Dummy spec, do not try to build, use kernel.spec instead"
exit 1


%build
echo "Dummy spec, do not try to build, use kernel.spec instead"
exit 1

%install
echo "Dummy spec, do not try to build, use kernel.spec instead"
exit 1

%files
%doc



%changelog

