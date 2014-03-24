# default to pvops build
%{!?build_flavor:%define build_flavor pvops}

%if 0%{?qubes_builder}
%define _sourcedir %(pwd)
%endif

#%define _unpackaged_files_terminate_build 0
%define variant %{build_flavor}.qubes
%define plainrel %(cat rel-%{build_flavor})
%define rel %{plainrel}.%{variant}
%define version %(cat version-%{build_flavor})

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
kernel module packages) against the %build_flavor flavor of the kernel.

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

