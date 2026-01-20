defmodule Micelio.Authorization do
  @moduledoc """
  Authorization policies for Micelio resources.
  """
  use LetMe.Policy, error_reason: :forbidden

  object :organization do
    action :create do
      allow(:authenticated_as_user)
    end

    action :read do
      allow(:organization_member)
    end

    action :update do
      allow(:organization_admin)
    end

    action :delete do
      allow(:organization_admin)
    end
  end

  object :membership do
    action :read do
      allow(:organization_member)
    end

    action :create do
      allow(:organization_admin)
    end

    action :update do
      allow(:organization_admin)
    end

    action :delete do
      allow(:organization_admin)
    end
  end

  object :project do
    action :create do
      allow(:organization_admin)
    end

    action :read do
      allow(:project_public)
      allow(:project_member)
    end

    action :update do
      allow(:project_admin)
    end

    action :delete do
      allow(:organization_admin)
    end

    action :write do
      allow(:project_admin)
    end
  end
end
